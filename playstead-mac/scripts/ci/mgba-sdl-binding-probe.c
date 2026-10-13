/*
 * Read-only SDL controller metadata probe for the mGBA 0.10.5 Mac adapter.
 *
 * Build against SDL release-2.30.7 (9519b9916cd29a14587af0507292f2bd31dd5752),
 * the revision embedded in the pinned mGBA macOS executable. The probe does
 * not poll button states, open Playstead, or launch mGBA. Run it only while
 * the intended controller is connected; the output stays local/private.
 */
#include <SDL.h>
#include <stdio.h>

static void print_button(SDL_GameController *controller, SDL_GameControllerButton button) {
    SDL_GameControllerButtonBind binding = SDL_GameControllerGetBindForButton(controller, button);
    const char *name = SDL_GameControllerGetStringForButton(button);
    if (binding.bindType == SDL_CONTROLLER_BINDTYPE_BUTTON) {
        printf("  %s button %d\n", name, binding.value.button);
    } else if (binding.bindType == SDL_CONTROLLER_BINDTYPE_HAT) {
        printf("  %s hat %d mask %d\n", name, binding.value.hat.hat, binding.value.hat.hat_mask);
    } else if (binding.bindType == SDL_CONTROLLER_BINDTYPE_AXIS) {
        printf("  %s axis %d\n", name, binding.value.axis);
    } else {
        printf("  %s unbound\n", name);
    }
}

static void print_axis(SDL_GameController *controller, SDL_GameControllerAxis axis) {
    SDL_GameControllerButtonBind binding = SDL_GameControllerGetBindForAxis(controller, axis);
    const char *name = SDL_GameControllerGetStringForAxis(axis);
    if (binding.bindType == SDL_CONTROLLER_BINDTYPE_AXIS) {
        printf("  %s axis %d\n", name, binding.value.axis);
    } else {
        printf("  %s unbound\n", name);
    }
}

int main(void) {
    SDL_version version;
    SDL_GetVersion(&version);
    if (version.major != 2 || version.minor != 30 || version.patch != 7) {
        fprintf(stderr, "Expected SDL 2.30.7; found %u.%u.%u\n",
                version.major, version.minor, version.patch);
        return 2;
    }
    if (SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "SDL controller initialization failed: %s\n", SDL_GetError());
        return 3;
    }

    int count = SDL_NumJoysticks();
    printf("SDL 2.30.7 joystick count: %d\n", count);
    for (int index = 0; index < count; ++index) {
        SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(index);
        char guid_string[33] = {0};
        SDL_JoystickGetGUIDString(guid, guid_string, sizeof(guid_string));
        printf("device %d: name=%s guid=%s gamecontroller=%d\n", index,
               SDL_JoystickNameForIndex(index), guid_string,
               SDL_IsGameController(index));
        if (!SDL_IsGameController(index)) {
            continue;
        }
        SDL_GameController *controller = SDL_GameControllerOpen(index);
        if (!controller) {
            fprintf(stderr, "device %d open failed: %s\n", index, SDL_GetError());
            continue;
        }
        const SDL_GameControllerButton buttons[] = {
            SDL_CONTROLLER_BUTTON_A, SDL_CONTROLLER_BUTTON_B,
            SDL_CONTROLLER_BUTTON_X, SDL_CONTROLLER_BUTTON_Y,
            SDL_CONTROLLER_BUTTON_BACK, SDL_CONTROLLER_BUTTON_START,
            SDL_CONTROLLER_BUTTON_LEFTSHOULDER, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
            SDL_CONTROLLER_BUTTON_DPAD_UP, SDL_CONTROLLER_BUTTON_DPAD_DOWN,
            SDL_CONTROLLER_BUTTON_DPAD_LEFT, SDL_CONTROLLER_BUTTON_DPAD_RIGHT
        };
        for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); ++i) {
            print_button(controller, buttons[i]);
        }
        print_axis(controller, SDL_CONTROLLER_AXIS_LEFTX);
        print_axis(controller, SDL_CONTROLLER_AXIS_LEFTY);
        SDL_GameControllerClose(controller);
    }
    SDL_Quit();
    return count > 0 ? 0 : 4;
}
