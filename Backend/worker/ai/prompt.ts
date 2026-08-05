// The system prompt is generated from prompts/meal-v5.md; this module only adds
// the user turn, which is the one string that legitimately differs between the
// proxy and the app.
export { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt.generated";

export const MEAL_RECOGNITION_USER_PROMPT = "Classify the meal closest to the camera.";
