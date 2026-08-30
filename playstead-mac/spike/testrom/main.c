/* savetest.gba — a minimal homebrew GBA test title, written for this spike
 * (Playstead project). MIT license; not derived from any third-party
 * homebrew, SDK, or Nintendo source.
 *
 * Purpose: demonstrably write SRAM (probe 3, D-03 owner ruling) without
 * requiring simulated controller/keyboard input, so the save-flush
 * observability probe can run fully automated. Boots, writes an initial
 * SRAM save record, fills the screen with a color derived from a counter
 * (visual proof-of-life for the human-check step), and increments +
 * re-saves the counter to SRAM roughly every 5 seconds (300 frames @ 60fps).
 */

/* "SRAM_Vnnn" is the marker string GBA emulators (including mGBA) scan the
 * ROM image for to auto-detect the save type as battery-backed SRAM. */
const char save_type_marker[] = "SRAM_V113";

#define REG_DISPCNT (*(volatile unsigned short *)0x04000000)
#define REG_VCOUNT (*(volatile unsigned short *)0x04000006)
#define SRAM ((volatile unsigned char *)0x0E000000)
#define VRAM ((volatile unsigned short *)0x06000000)

static void wait_vblank(void) {
    while (REG_VCOUNT >= 160) {
    }
    while (REG_VCOUNT < 160) {
    }
}

static void save_counter(unsigned int counter) {
    SRAM[0] = 0xAA;
    SRAM[1] = 0x55;
    SRAM[2] = (unsigned char)(counter & 0xFF);
    SRAM[3] = (unsigned char)((counter >> 8) & 0xFF);
    SRAM[4] = (unsigned char)((counter >> 16) & 0xFF);
    SRAM[5] = (unsigned char)((counter >> 24) & 0xFF);
}

int main(void) {
    REG_DISPCNT = 0x0403; /* Mode 3, BG2 enable */

    unsigned int counter = 0;
    unsigned int frame = 0;

    save_counter(counter);

    while (1) {
        wait_vblank();
        frame++;

        unsigned short shade = (unsigned short)(counter & 0x1F);
        unsigned short color = (unsigned short)(shade | (shade << 5) | (shade << 10));
        for (int i = 0; i < 240 * 160; i++) {
            VRAM[i] = color;
        }

        if (frame % 300 == 0) {
            counter++;
            save_counter(counter);
        }
    }

    return 0;
}
