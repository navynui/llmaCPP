# TODO: LLM Manager Enhancements

## 💬 Chat Interface
- [ ] **Simplify Model Logic**: Remove the need to switch models once a chat session starts.
- [ ] **Direct Interaction**: Ensure the chat interface simply uses the currently loaded model on the server without requiring explicit selection/switching within the chat view.

## ⚙️ Server Tab
- [ ] **Streamline Model Switching**: Improve the UX for changing models.
- [ ] **Model Status**: 
    - Clearly indicate the **Default** and **Currently Loaded** model.
    - Implement visual status indicators during the switching process:
        - `Loading...` (while the server is updating/restarting).
        - `Loaded` (once the model is fully active).
- [ ] **Container Control**:
    - Implement a primary **Start/Stop** button for the `llama-server` Docker container.
    - Implement an **Unload Model** button (clears VRAM/model without stopping the container).

## 🧹 Cleanup
- [ ] **Remove Quick-load**: Delete "Quick-load shortcuts" and all associated UI components/logic.

## 🔍 Monitoring & Automation
- [ ] **Switching Log Monitoring**: Monitor server logs specifically during model switching for critical errors:
    - `ERROR`, `Out of Memory`, `Load fail`, `Wrong architecture`, etc.
    - Implement a clear notification system to alert the user if a switch fails.
- [ ] **Model Preset Auto-Update**: 
    - Add an **Update** button to the Model Router Presets.
    - When clicked: scan the `models/` folder for `.gguf` files not present in `models.ini`.
    - Automatically add new models to `models.ini` and notify the user.

