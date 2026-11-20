import asyncio
import unittest
from aiohttp.test_utils import TestClient, TestServer
from server.rendezvous import create_app, STATE

OWNER = "o" * 64
PAIR = "p" * 64
DEVICE = "test-device-0000000001"


class BrokerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.now = 0
        self.client = TestClient(TestServer(create_app(lambda: self.now)))
        await self.client.start_server()
        response = await self.client.post('/v1/register', json={
            'id': DEVICE, 'key': OWNER, 'pair_key': PAIR, 'name': 'Actual host', 'platform': 'mac'})
        self.assertEqual(response.status, 200)

    async def asyncTearDown(self):
        await self.client.close()

    def auth(self, token):
        return {'Authorization': 'Bearer ' + token}

    async def join(self, key=PAIR):
        response = await self.client.post('/v1/connect', json={
            'target': DEVICE, 'key': key, 'name': 'Any controller', 'platform': 'windows'})
        return response

    async def send(self, session, token, kind, payload=None, identity='message-00000001'):
        return await self.client.post(f'/v1/sessions/{session}/signals', headers=self.auth(token), json={
            'type': kind, 'data': payload or {}, 'message_id': identity})

    async def test_pair_key_cannot_impersonate_host_or_read_inbox(self):
        r = await self.client.get(f'/v1/devices/{DEVICE}/inbox', headers=self.auth(PAIR))
        self.assertEqual(r.status, 401)
        session = await (await self.join()).json()
        r = await self.send(session['id'], PAIR, 'accept')
        self.assertEqual(r.status, 401)
        r = await self.send(session['id'], session['token'], 'accept')
        self.assertEqual(r.status, 409)

    async def test_consent_then_bidirectional_signals_and_retry_deduplication(self):
        session = await (await self.join()).json()
        sid, token = session['id'], session['token']
        r = await self.send(sid, token, 'offer', {'sdp': 'v=0'})
        self.assertEqual(r.status, 409)
        self.assertEqual((await self.send(sid, OWNER, 'accept')).status, 200)
        r = await self.client.get(f'/v1/sessions/{sid}/signals?after=0', headers=self.auth(token))
        events = (await r.json())['events']
        self.assertEqual([e['type'] for e in events], ['accepted'])
        for _ in range(2):
            self.assertEqual((await self.send(sid, token, 'offer', {'sdp': 'v=0'}, 'same-message-000001')).status, 200)
        r = await self.client.get(f'/v1/sessions/{sid}/signals?after=0', headers=self.auth(OWNER))
        self.assertEqual([e['type'] for e in (await r.json())['events']], ['offer'])
        self.assertEqual((await self.send(sid, OWNER, 'answer', {'sdp': 'answer'}, 'answer-message-001')).status, 200)
        r = await self.client.get(f'/v1/sessions/{sid}/signals?after=1', headers=self.auth(token))
        self.assertEqual((await r.json())['events'][0]['data']['sdp'], 'answer')

    async def test_offline_missing_and_unknown_device_do_not_create_phantom_hosts(self):
        self.assertEqual((await self.join('x' * 64)).status, 403)
        self.now = 16
        self.assertEqual((await self.join()).status, 409)
        self.assertEqual(len(self.client.server.app[STATE].sessions), 0)

    async def test_existing_identity_cannot_be_taken_over(self):
        r = await self.client.post('/v1/register', json={
            'id': DEVICE, 'key': 'x' * 64, 'pair_key': PAIR, 'name': 'Attacker', 'platform': 'android'})
        self.assertEqual(r.status, 403)

    async def test_session_isolation_close_and_bounds(self):
        a = await (await self.join()).json()
        b = await (await self.join()).json()
        r = await self.send(a['id'], b['token'], 'close')
        self.assertEqual(r.status, 401)
        self.assertEqual((await self.send(a['id'], OWNER, 'close')).status, 200)
        self.assertEqual((await self.send(a['id'], a['token'], 'offer')).status, 410)
        r = await self.client.get(f"/v1/sessions/{a['id']}/signals?after=-1", headers=self.auth(OWNER))
        self.assertEqual(r.status, 400)
        for i in range(7):
            self.assertEqual((await self.join()).status, 200)
        self.assertEqual((await self.join()).status, 429)

    async def test_stale_mailboxes_expire(self):
        a = await (await self.join()).json()
        self.now = 601
        self.client.server.app[STATE].prune()
        self.assertNotIn(a['id'], self.client.server.app[STATE].sessions)


if __name__ == '__main__':
    unittest.main()
