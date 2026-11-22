#include "napi_helpers.h"
#include <array>
#include <dlfcn.h>

namespace {
void *MihomoSymbol(const char *name)
{
    // Keep Go's shared library loaded for the lifetime of this process.
    static void *library = dlopen("libmihomo.so", RTLD_LAZY | RTLD_LOCAL);
    return library ? dlsym(library, name) : nullptr;
}

napi_value CheckMihomoProfile(napi_env env, napi_callback_info info)
{
    napi_value arg;
    size_t count = 1;
    std::string config;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1
        || !ReadString(env, arg, config, 4 * 1024 * 1024)) {
        return Boolean(env, false);
    }
    using CheckProfile = int (*)(char *);
    static auto check = reinterpret_cast<CheckProfile>(MihomoSymbol("MBCheckProfile"));
    return Boolean(env, check != nullptr && check(config.data()) == 0);
}

napi_value MihomoStart(napi_env env, napi_callback_info info)
{
    std::array<napi_value, 2> args{};
    size_t count = args.size();
    std::string config, directory;
    if (napi_get_cb_info(env, info, &count, args.data(), nullptr, nullptr) != napi_ok || count != args.size()
        || !ReadString(env, args[0], config, 4 * 1024 * 1024) || !ReadString(env, args[1], directory, 4096)) {
        return Boolean(env, false);
    }
    static auto start = reinterpret_cast<int (*)(char *, char *)>(MihomoSymbol("MBStart"));
    return Boolean(env, start != nullptr && start(config.data(), directory.data()) == 0);
}

napi_value MihomoStatus(napi_env env, napi_callback_info)
{
    static auto status = reinterpret_cast<char *(*)()>(MihomoSymbol("MBStatus"));
    static auto release = reinterpret_cast<void (*)(char *)>(MihomoSymbol("MBFree"));
    napi_value result = nullptr;
    if (status && release) {
        char *value = status();
        napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
        release(value);
    } else {
        napi_create_string_utf8(env, "{\"state\":\"stopped\"}", NAPI_AUTO_LENGTH, &result);
    }
    return result;
}

napi_value MihomoSetTunnel(napi_env env, napi_callback_info info)
{
    napi_value arg;
    size_t count = 1;
    int32_t fd = -1;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1
        || napi_get_value_int32(env, arg, &fd) != napi_ok || fd <= 0) {
        return Boolean(env, false);
    }
    static auto setTunnel = reinterpret_cast<int (*)(int)>(MihomoSymbol("MBSetTunnel"));
    return Boolean(env, setTunnel != nullptr && setTunnel(fd) == 0);
}

napi_value MihomoStop(napi_env env, napi_callback_info)
{
    static auto stop = reinterpret_cast<void (*)()>(MihomoSymbol("MBStop"));
    if (stop) {
        stop();
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value MihomoRules(napi_env env, napi_callback_info info)
{
    std::array<napi_value, 2> args{};
    size_t count = args.size();
    std::string config, rules;
    char *value = nullptr;
    static auto read = reinterpret_cast<char *(*)(char *)>(MihomoSymbol("MBReadRules"));
    static auto replace = reinterpret_cast<char *(*)(char *, char *)>(MihomoSymbol("MBReplaceRules"));
    static auto release = reinterpret_cast<void (*)(char *)>(MihomoSymbol("MBFree"));
    if (release && napi_get_cb_info(env, info, &count, args.data(), nullptr, nullptr) == napi_ok
        && count >= 1 && ReadString(env, args[0], config, 4 * 1024 * 1024)) {
        if (count == 1 && read) {
            value = read(config.data());
        } else if (count == 2 && replace && ReadString(env, args[1], rules, 4 * 1024 * 1024)) {
            value = replace(config.data(), rules.data());
        }
    }
    napi_value result = nullptr;
    napi_create_string_utf8(env, value ? value : "", NAPI_AUTO_LENGTH, &result);
    if (value) {
        release(value);
    }
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
    static auto control = reinterpret_cast<int (*)(char *, char *, char *)>(MihomoSymbol("MBControl"));
    return Boolean(env, control != nullptr && control(action.data(), group.data(), node.data()) == 0);
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor methods[] = {
        {"checkProfile", nullptr, CheckMihomoProfile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, MihomoStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, MihomoStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setTunnel", nullptr, MihomoSetTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, MihomoStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"control", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rules", nullptr, MihomoRules, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(methods) / sizeof(methods[0]), methods);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "mh_harmony", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterMihomoModule()
{
    napi_module_register(&module);
}
