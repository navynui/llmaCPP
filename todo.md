# TODO: LLM Manager Enhancements

## 🔍 Monitoring & Automation
- [ ] **Switching Log Monitoring**: Monitor server logs specifically during model switching for critical errors:
    - `ERROR`, `Out of Memory`, `Load fail`, `Loading error`, `Wrong architecture`, etc.
    - Implement a clear notification system to alert the user if a switch fails.
- [x] **Model Preset Auto-Update**: 
    - Add an **Update** button to the Model Router Presets.
    - When clicked: scan the `models/` folder for `.gguf` files not present in `models.ini`.
    - Automatically add new models to `models.ini` and notify the user.

## 🖼️ Image Generation & ComfyUI
- [ ] **Fix batch image generation fail**: Need to figure out the python backend and comfyUI

