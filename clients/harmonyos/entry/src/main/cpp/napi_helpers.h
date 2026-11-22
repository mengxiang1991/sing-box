#pragma once

#include <napi/native_api.h>
#include <string>

inline bool ReadString(napi_env env, napi_value value, std::string &text, size_t limit)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > limit) {
        return false;
    }
    text.resize(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, text.data(), text.size(), &copied) != napi_ok || copied != length) {
        return false;
    }
    text.resize(length);
    return text.find('\0') == std::string::npos;
}

inline napi_value Boolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}
