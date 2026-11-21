// CI inventory only. The supplied detector performs the codec probing itself.
#include <dxgi.h>
#include <wrl/client.h>
#include <cstdint>
#include <cstdio>

int main() {
    using Microsoft::WRL::ComPtr;
    ComPtr<IDXGIFactory1> factory;
    HRESULT result = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(result)) {
        std::fprintf(stderr, "CreateDXGIFactory1 failed: 0x%08lx\n", static_cast<unsigned long>(result));
        return 1;
    }
    std::printf("[");
    bool first = true;
    for (UINT index = 0; ; ++index) {
        ComPtr<IDXGIAdapter1> adapter;
        result = factory->EnumAdapters1(index, &adapter);
        if (result == DXGI_ERROR_NOT_FOUND) break;
        if (FAILED(result)) return 2;
        DXGI_ADAPTER_DESC1 desc{};
        result = adapter->GetDesc1(&desc);
        if (FAILED(result)) return 3;
        // Keep both LUID halves as bits, then emit a decimal string to avoid
        // loss of integer precision in JSON readers. This is not a GPU ordinal.
        const auto luid = (static_cast<std::uint64_t>(static_cast<std::uint32_t>(desc.AdapterLuid.HighPart)) << 32)
                        | desc.AdapterLuid.LowPart;
        std::printf("%s{\"index\":%u,\"vendor_id\":%u,\"device_id\":%u,\"adapter_id\":\"%llu\",\"flags\":%u}",
                    first ? "" : ",", index, desc.VendorId, desc.DeviceId,
                    static_cast<unsigned long long>(luid), desc.Flags);
        first = false;
    }
    std::printf("]\n");
    return 0;
}
