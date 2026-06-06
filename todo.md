# TODO: LLM Manager Enhancements

## 🚨 Regressions & Bugs
- [x] **MD Viewer**: Dropdown still shows "Loading files..." and does not render selected files.
- [x] **Chat Interface**: Still switches models; needs to strictly use the currently loaded model on the server.

## 💬 Chat Interface
- [x] **Simplify Model Logic**: Remove the need to switch models once a chat session starts.
- [x] **Direct Interaction**: Ensure the chat interface simply uses the currently loaded model on the server without requiring explicit selection/switching within the chat view.

## ⚙️ Server Tab
- [x] **Streamline Model Switching**: Improve the UX for changing models.
- [x] **Model Status**: 
    - Clearly indicate the **Default** and **Currently Loaded** model.
    - Implement visual status indicators during the switching process:
        - `Loading...` (while the server is updating/restarting).
        - `Loaded` (once the model is fully active).
- [x] **Container Control**:
    - Implement a primary **Start/Stop** button for the `llama-server` Docker container.
    - Implement an **Unload Model** button (clears VRAM/model without stopping the container).

## 🧹 Cleanup
- [x] **Remove Quick-load**: Delete "Quick-load shortcuts" and all associated UI components/logic.

## 📄 MD / Document Viewer
- [x] **Dropdown Model Selection**: Modify MD tabs to have a dropdown selection for selecting the MD file to read.
- [x] **Layout Optimization**: Place the dropdown above the reader area so the rendered text occupies the full width.

## 🔍 Monitoring & Automation
- [x] **Switching Log Monitoring**: Monitor server logs specifically during model switching for critical errors:
    - `ERROR`, `Out of Memory`, `Load fail`, `Wrong architecture`, etc.
    - Implement a clear notification system to alert the user if a switch fails.
- [x] **Model Preset Auto-Update**: 
    - Add an **Update** button to the Model Router Presets.
    - When clicked: scan the `models/` folder for `.gguf` files not present in `models.ini`.
    - Automatically add new models to `models.ini` and notify the user.

