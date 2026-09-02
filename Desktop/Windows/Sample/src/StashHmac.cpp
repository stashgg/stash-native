#include "Sample.hpp"

#include <bcrypt.h>
#include <wincrypt.h>

#include <chrono>

namespace sample {

static bool base64Decode(const std::string &text, std::vector<BYTE> &out) {
    DWORD size = 0;
    if (!CryptStringToBinaryA(text.c_str(), 0, CRYPT_STRING_BASE64, nullptr, &size, nullptr, nullptr) || size == 0) {
        return false;
    }
    out.resize(size);
    return CryptStringToBinaryA(text.c_str(), 0, CRYPT_STRING_BASE64, out.data(), &size, nullptr, nullptr) != FALSE;
}

static std::string base64Encode(const std::vector<BYTE> &bytes) {
    DWORD size = 0;
    if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &size)) {
        return "";
    }
    std::string out(size, '\0');
    if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, &out[0], &size)) {
        return "";
    }
    out.resize(size);
    while (!out.empty() && out.back() == '\0') {
        out.pop_back();
    }
    return out;
}

bool hmacSignature(const std::string &appId, const std::string &ingressSecretB64, const std::string &body, std::string &out) {
    std::vector<BYTE> key;
    if (!base64Decode(ingressSecretB64, key)) {
        return false;
    }
    long long unixMillis = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    std::string message = std::to_string(unixMillis) + "." + body;

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, BCRYPT_ALG_HANDLE_HMAC_FLAG) != 0) {
        return false;
    }
    std::vector<BYTE> mac(32);
    BCRYPT_HASH_HANDLE hash = nullptr;
    bool ok = BCryptCreateHash(algorithm, &hash, nullptr, 0, key.data(), static_cast<ULONG>(key.size()), 0) == 0 &&
              BCryptHashData(hash, reinterpret_cast<PUCHAR>(&message[0]), static_cast<ULONG>(message.size()), 0) == 0 &&
              BCryptFinishHash(hash, mac.data(), static_cast<ULONG>(mac.size()), 0) == 0;
    if (hash != nullptr) {
        BCryptDestroyHash(hash);
    }
    BCryptCloseAlgorithmProvider(algorithm, 0);
    if (!ok) {
        return false;
    }
    out = "v1;" + appId + ";" + std::to_string(unixMillis) + ";" + base64Encode(mac);
    return true;
}

}  // namespace sample
