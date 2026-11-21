#include <napi/native_api.h>
#include <array>
#include <string>

extern "C" {
int SBStart(char *config, char *directory, char *interfaceName, int network);
char *SBStatus();
int SBSetTunnel(int fd);
int SBControl(char *action, char *group, char *node);
void SBStop();
void SBFree(char *value);
}

namespace {
bool ReadString(napi_env env, napi_value value, std::string &text, size_t limit)
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

napi_value Boolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value Start(napi_env env, napi_callback_info info)
{
    std::array<napi_value, 4> args{};
    size_t count = args.size();
    std::string config, directory, interfaceName;
    int32_t network = -1;
    if (napi_get_cb_info(env, info, &count, args.data(), nullptr, nullptr) != napi_ok || count != args.size()
        || !ReadString(env, args[0], config, 4 * 1024 * 1024)
        || !ReadString(env, args[1], directory, 4096)
        || !ReadString(env, args[2], interfaceName, 128)
        || napi_get_value_int32(env, args[3], &network) != napi_ok || network < 0) {
        return Boolean(env, false);
    }
    return Boolean(env, SBStart(config.data(), directory.data(), interfaceName.data(), network) == 0);
}

napi_value Status(napi_env env, napi_callback_info)
{
    char *value = SBStatus();
    napi_value result = nullptr;
    napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
    SBFree(value);
    return result;
}

napi_value SetTunnel(napi_env env, napi_callback_info info)
{
    napi_value arg;
    size_t count = 1;
    int32_t fd = -1;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1
        || napi_get_value_int32(env, arg, &fd) != napi_ok || fd < 0) {
        return Boolean(env, false);
    }
    return Boolean(env, SBSetTunnel(fd) == 0);
}

napi_value Stop(napi_env env, napi_callback_info)
{
    SBStop();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value Control(napi_env env, napi_callback_info info)
{
    std::array<napi_value, 3> args{};
    size_t count = args.size();
    std::string action, group, node;
    if (napi_get_cb_info(env, info, &count, args.data(), nullptr, nullptr) != napi_ok || count != args.size()
        || !ReadString(env, args[0], action, 16) || !ReadString(env, args[1], group, 4096)
        || !ReadString(env, args[2], node, 4096)) {
        return Boolean(env, false);
    }
    return Boolean(env, SBControl(action.data(), group.data(), node.data()) == 0);
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor methods[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setTunnel", nullptr, SetTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"control", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(methods) / sizeof(methods[0]), methods);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "sb_harmony", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterSingBoxModule()
{
    napi_module_register(&module);
}
