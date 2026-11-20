"""Real ICE + DTLS/SCTP + RTP over the broker; synthetic video, not screen parity."""
import asyncio
import unittest
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCConfiguration, VideoStreamTrack
from server.test_rendezvous import BrokerTests, OWNER


class TransportTests(BrokerTests):
    async def test_offer_answer_delivers_real_video_and_bidirectional_control(self):
        host = RTCPeerConnection(RTCConfiguration(iceServers=[]))
        controller = RTCPeerConnection(RTCConfiguration(iceServers=[]))
        opened = asyncio.Event()
        delivered = asyncio.Event()
        received_frame = asyncio.Event()
        tasks = []
        channel = controller.createDataChannel('CONTROL_DATA_CHANNEL', ordered=True)
        channel.on('open', opened.set)
        channel.on('message', lambda msg: delivered.set() if msg == b'host-ack' else None)
        @host.on('datachannel')
        def on_channel(dc):
            @dc.on('message')
            def receive(msg):
                if msg == b'controller-input': dc.send(b'host-ack')
        @controller.on('track')
        def on_track(track):
            async def consume():
                frame = await track.recv()
                if frame.width > 0 and frame.height > 0: received_frame.set()
            tasks.append(asyncio.create_task(consume()))
        host.addTrack(VideoStreamTrack())
        controller.addTransceiver('video', direction='recvonly')
        session = await (await self.join()).json()
        sid, token = session['id'], session['token']
        try:
            await self.send(sid, OWNER, 'accept')
            await controller.setLocalDescription(await controller.createOffer())
            await self.send(sid, token, 'offer', {'sdp': controller.localDescription.sdp}, 'offer-message-001')
            response = await self.client.get(f'/v1/sessions/{sid}/signals?after=0', headers=self.auth(OWNER))
            offer = (await response.json())['events'][0]['data']['sdp']
            await host.setRemoteDescription(RTCSessionDescription(sdp=offer, type='offer'))
            await host.setLocalDescription(await host.createAnswer())
            await self.send(sid, OWNER, 'answer', {'sdp': host.localDescription.sdp}, 'answer-message-001')
            response = await self.client.get(f'/v1/sessions/{sid}/signals?after=1', headers=self.auth(token))
            answer = (await response.json())['events'][0]['data']['sdp']
            await controller.setRemoteDescription(RTCSessionDescription(sdp=answer, type='answer'))
            await asyncio.wait_for(opened.wait(), 15)
            channel.send(b'controller-input')
            await asyncio.wait_for(delivered.wait(), 10)
            await asyncio.wait_for(received_frame.wait(), 10)
            self.assertEqual(controller.connectionState, 'connected')
            self.assertEqual(host.connectionState, 'connected')
        finally:
            await controller.close()
            await host.close()
            for task in tasks: task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)


if __name__ == '__main__':
    unittest.main()
