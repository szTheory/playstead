/*
 * Playstead's private SDL metadata/input companion. Build only with the
 * SDL release-2.30.7 source revision pinned in build-mgba-sdl-input-bridge.sh.
 * The helper emits bounded JSON Lines; no ROM/save data or persistent
 * controller identifiers are written to disk.
 */
#include <SDL.h>
#include <stdio.h>
#include <string.h>

#define MAX_CONTROLLERS 8
#define MAX_NAME 192

static const char *button_name(SDL_GameControllerButton button) {
    switch (button) {
    case SDL_CONTROLLER_BUTTON_A: return "buttonA";
    case SDL_CONTROLLER_BUTTON_B: return "buttonB";
    case SDL_CONTROLLER_BUTTON_X: return "buttonX";
    case SDL_CONTROLLER_BUTTON_Y: return "buttonY";
    case SDL_CONTROLLER_BUTTON_BACK: return "buttonBack";
    case SDL_CONTROLLER_BUTTON_START: return "buttonStart";
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return "leftShoulder";
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return "rightShoulder";
    case SDL_CONTROLLER_BUTTON_DPAD_UP: return "dpadUp";
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return "dpadDown";
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return "dpadLeft";
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return "dpadRight";
    default: return NULL;
    }
}

static const char *axis_name(SDL_GameControllerAxis axis) {
    switch (axis) {
    case SDL_CONTROLLER_AXIS_LEFTX: return "leftX";
    case SDL_CONTROLLER_AXIS_LEFTY: return "leftY";
    case SDL_CONTROLLER_AXIS_RIGHTX: return "rightX";
    case SDL_CONTROLLER_AXIS_RIGHTY: return "rightY";
    case SDL_CONTROLLER_AXIS_TRIGGERLEFT: return "leftTrigger";
    case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: return "rightTrigger";
    default: return NULL;
    }
}

static const char *button_mapping_name(SDL_GameControllerButton button) {
    switch (button) {
    case SDL_CONTROLLER_BUTTON_A: return "a";
    case SDL_CONTROLLER_BUTTON_B: return "b";
    case SDL_CONTROLLER_BUTTON_X: return "x";
    case SDL_CONTROLLER_BUTTON_Y: return "y";
    case SDL_CONTROLLER_BUTTON_BACK: return "back";
    case SDL_CONTROLLER_BUTTON_START: return "start";
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return "leftshoulder";
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return "rightshoulder";
    case SDL_CONTROLLER_BUTTON_DPAD_UP: return "dpup";
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return "dpdown";
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return "dpleft";
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return "dpright";
    default: return NULL;
    }
}

static void json_string(const char *value);

static void write_raw_mapping(SDL_GameController *controller, const char *display_name, const char *mapping_name) {
    char *full = SDL_GameControllerMapping(controller);
    if (!full) { json_string(display_name); printf(":{\"type\":\"unbound\"}"); return; }
    char *save = NULL;
    (void)strtok_r(full, ",", &save); /* GUID */
    (void)strtok_r(NULL, ",", &save); /* controller name */
    char *entry;
    int written = 0;
    while ((entry = strtok_r(NULL, ",", &save))) {
        char *colon = strchr(entry, ':');
        if (!colon) continue;
        *colon = '\0';
        if (strcmp(entry, mapping_name) != 0) continue;
        char *raw = colon + 1;
        json_string(display_name); putchar(':');
        if (raw[0] == 'b' && raw[1]) {
            char *end = NULL; long value = strtol(raw + 1, &end, 10);
            if (end && *end == '\0' && value >= 0 && value < 256) printf("{\"type\":\"button\",\"index\":%ld}", value);
            else printf("{\"type\":\"unbound\"}");
        } else if (raw[0] == 'h') {
            char *dot = strchr(raw + 1, '.');
            if (!dot) { printf("{\"type\":\"unbound\"}"); }
            else {
                *dot = '\0'; char *end = NULL;
                long hat = strtol(raw + 1, &end, 10); char *mask_end = NULL;
                long mask = strtol(dot + 1, &mask_end, 0);
                if (end && *end == '\0' && mask_end && *mask_end == '\0' && hat >= 0 && hat < 32 && mask > 0 && mask <= 15)
                    printf("{\"type\":\"hat\",\"index\":%ld,\"mask\":%ld}", hat, mask);
                else printf("{\"type\":\"unbound\"}");
            }
        } else {
            int sign = 1; char *axis = raw;
            if (raw[0] == '+' || raw[0] == '-') { sign = raw[0] == '-' ? -1 : 1; axis = raw + 1; }
            if (axis[0] == 'a' && axis[1]) {
                char *end = NULL; long value = strtol(axis + 1, &end, 10);
                if (end && *end == '\0' && value >= 0 && value < 256)
                    printf("{\"type\":\"axis\",\"index\":%ld,\"sign\":%d}", value, sign);
                else printf("{\"type\":\"unbound\"}");
            } else printf("{\"type\":\"unbound\"}");
        }
        written = 1; break;
    }
    if (!written) { json_string(display_name); printf(":{\"type\":\"unbound\"}"); }
    SDL_free(full);
}

static void json_string(const char *value) {
    putchar('"');
    for (size_t i = 0; value && value[i] && i < MAX_NAME; ++i) {
        unsigned char c = (unsigned char)value[i];
        if (c == '"' || c == '\\') { putchar('\\'); putchar(c); }
        else if (c >= 0x20) putchar(c);
    }
    putchar('"');
}

static int emit_snapshot(unsigned long generation) {
    int total = SDL_NumJoysticks(), count = 0;
    if (total > MAX_CONTROLLERS) return 5;
    printf("{\"kind\":\"snapshot\",\"generation\":%lu,\"devices\":[", generation);
    for (int i = 0; i < total; ++i) {
        if (!SDL_IsGameController(i)) continue;
        SDL_GameController *controller = SDL_GameControllerOpen(i);
        if (!controller) return 6;
        SDL_Joystick *joystick = SDL_GameControllerGetJoystick(controller);
        SDL_JoystickGUID guid = SDL_JoystickGetGUID(joystick);
        char guid_text[33] = {0}; SDL_JoystickGetGUIDString(guid, guid_text, sizeof(guid_text));
        if (count++) putchar(',');
        printf("{\"instanceID\":%d,\"guid\":", SDL_JoystickInstanceID(joystick));
        json_string(guid_text); printf(",\"name\":"); json_string(SDL_GameControllerName(controller));
        printf(",\"bindings\":{");
        int comma = 0;
        for (int b = 0; b < SDL_CONTROLLER_BUTTON_MAX; ++b) {
            const char *name = button_name((SDL_GameControllerButton)b);
            if (!name) continue;
            if (comma++) putchar(',');
            write_raw_mapping(controller, name, button_mapping_name((SDL_GameControllerButton)b));
        }
        for (int a = 0; a < SDL_CONTROLLER_AXIS_MAX; ++a) {
            const char *name = axis_name((SDL_GameControllerAxis)a);
            if (!name) continue;
            if (comma++) putchar(',');
            static const char *axis_tokens[] = {"leftx", "lefty", "rightx", "righty", "lefttrigger", "righttrigger"};
            write_raw_mapping(controller, name, axis_tokens[a]);
        }
        printf("}}"); SDL_GameControllerClose(controller);
    }
    printf("]}\n"); fflush(stdout);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        SDL_version reported; SDL_GetVersion(&reported);
        printf("SDL %u.%u.%u\n", reported.major, reported.minor, reported.patch);
        return reported.major == 2 && reported.minor == 30 && reported.patch == 7 ? 0 : 3;
    }
    const int snapshot_only = argc == 2 && strcmp(argv[1], "--snapshot") == 0;
    const char *nonce = argc == 3 && strcmp(argv[1], "--stream") == 0 ? argv[2] : NULL;
    if (!snapshot_only && (!nonce || !*nonce || strlen(nonce) > 96)) return 2;
    SDL_version version; SDL_GetVersion(&version);
    if (version.major != 2 || version.minor != 30 || version.patch != 7) return 3;
    if (SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) != 0) return 4;
    SDL_JoystickEventState(SDL_ENABLE);
    unsigned long generation = 1;
    int status = emit_snapshot(generation);
    if (status || snapshot_only) { SDL_Quit(); return status; }
    SDL_Event event;
    while (SDL_WaitEvent(&event)) {
        if (event.type == SDL_JOYDEVICEADDED || event.type == SDL_JOYDEVICEREMOVED || event.type == SDL_CONTROLLERDEVICEREMAPPED) {
            ++generation;
            printf("{\"kind\":\"invalidate\",\"generation\":%lu}\n", generation);
            fflush(stdout);
            continue;
        }
        SDL_JoystickID instance = -1;
        const char *input = NULL;
        int pressed = 0;
        if (event.type == SDL_CONTROLLERBUTTONDOWN || event.type == SDL_CONTROLLERBUTTONUP) {
            instance = event.cbutton.which;
            input = button_name((SDL_GameControllerButton)event.cbutton.button);
            pressed = event.type == SDL_CONTROLLERBUTTONDOWN;
        }
        if (input) {
            printf("{\"kind\":\"edge\",\"nonce\":"); json_string(nonce);
            printf(",\"instanceID\":%d,\"input\":", (int)instance); json_string(input);
            printf(",\"pressed\":%s,\"generation\":%lu}\n", pressed ? "true" : "false", generation);
            fflush(stdout);
        }
    }
    SDL_Quit();
    return 0;
}
