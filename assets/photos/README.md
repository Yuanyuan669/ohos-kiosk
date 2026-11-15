Drop any .jpg / .png / .webp / .bmp here, then run:

    bash scripts/push-photos.sh

The board reads them from its own app sandbox, not from this folder, so nothing
here is needed at build time. Keep this directory light (a dozen shots is plenty;
decode is capped at 1280px edge to protect memory on the board).
