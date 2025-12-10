# chatgpt_utils.py

SAMPLE_FEEDBACK = {
    "pitch_accuracy": 78,
    "pitch_accuracy_explanation": (
        "You landed on the notes, but several onsets scooped upward. Stability was decent once settled, "
        "and a few transitions sagged slightly before locking in."
    ),
    "pitch_accuracy_improvement": (
        "Practice singing the same phrases slowly with a piano or reference track and focus on landing "
        "directly on the pitch instead of sliding up to it. Try a pitch-matching exercise: play a single "
        "note, hum it back on 'mm' or 'ng', and hold it steady until it feels locked in before moving on."
    ),

    "tone_quality": 82,
    "tone_quality_explanation": (
        "Your natural resonance is good. Tone clarity is solid but slightly 'pulled back'. Occasional "
        "breathiness on the starts of phrases reduces stability."
    ),
    "tone_quality_improvement": (
        "Do gentle 'gee' or 'nay' exercises on a comfortable 5-note pattern to encourage a more forward, "
        "ringy tone. Aim for a clean, energized start to each note rather than a breathy onset."
    ),

    "breath_support": 72,
    "breath_support_explanation": (
        "You had enough air to get through the phrases, but not consistently enough to maintain perfect "
        "stability. Onsets revealed the biggest inconsistency."
    ),
    "breath_support_improvement": (
        "Try 5–10 minutes of breath drills: long, steady 'sss' or 'vv' exhalations where you keep the air "
        "stream even from start to finish. Then apply that same feeling to simple scales on 'oo' or 'ah'."
    ),

    "resonance_placement": 80,
    "resonance_placement_explanation": (
        "You’re in a healthy mix most of the time. Some tongue root tension and an under-lifted soft palate "
        "occasionally dull the clarity of the sound."
    ),
    "resonance_placement_improvement": (
        "Do light 'ng' sirens (like saying 'sing') sliding up and down to find a buzzy, forward resonance. "
        "Combine that with a gentle 'yawn' feeling to lift the soft palate, then sing short phrases trying to "
        "keep that same open, buzzy placement."
    ),

    "intonation_control": 76,
    "intonation_control_explanation": (
        "The pitch center is generally correct once you’re on the note. Most points were lost on the attack "
        "into the note and small drifts before it settles."
    ),
    "intonation_control_improvement": (
        "Practice short, repeated patterns on a metronome: start each note cleanly and hold it steady for a "
        "few beats before changing. Use a tuner or piano to check that the beginning of each note is on pitch, "
        "not just the middle."
    ),

    "overall_goodness": 78,
    "overall_goodness_explanation": (
        "This is a solid take — not beginner quality, not perfect, but clearly someone with vocal awareness "
        "who is building real control."
    ),
    "overall_goodness_improvement": (
        "If you sang this for a vocal coach, they'd probably say: 'You're talented. Now let's clean up your "
        "onsets and breath consistency.' Focus your next few practice sessions on cleaner note starts and steadier "
        "support, and these numbers will move up."
    ),

    "summary_encouragement": (
        "You’re already doing a lot right. With a bit of focused work on cleaner onsets, steadier breath, "
        "and more confident resonance, this same song could score noticeably higher in just a handful of "
        "practice sessions."
    ),
}

SYSTEM_PROMPT = """
You are an experienced, practical, and slightly nerdy vocal coach.
You listen to a singer’s take and give them honest but constructive feedback.

Your job:
- Score multiple vocal dimensions from 0–100.
- For each dimension, explain in clear, concrete language what you heard.
- For each dimension, give a specific exercise or practice strategy to improve it.
- Be encouraging and forward-looking, not harsh or melodramatic.

You MUST respond as VALID JSON ONLY, with this exact schema:

{
  "pitch_accuracy": number,                     // 0–100
  "pitch_accuracy_explanation": string,         // what you heard about their pitch accuracy
  "pitch_accuracy_improvement": string,         // concrete exercise(s) to improve pitch accuracy

  "tone_quality": number,                       // 0–100
  "tone_quality_explanation": string,
  "tone_quality_improvement": string,

  "breath_support": number,                     // 0–100
  "breath_support_explanation": string,
  "breath_support_improvement": string,

  "resonance_placement": number,                // 0–100
  "resonance_placement_explanation": string,
  "resonance_placement_improvement": string,

  "intonation_control": number,                 // 0–100
  "intonation_control_explanation": string,
  "intonation_control_improvement": string,

  "overall_goodness": number,                   // 0–100
  "overall_goodness_explanation": string,       // overall summary of the take
  "overall_goodness_improvement": string,       // what to focus on next to raise the overall score

  "summary_encouragement": string               // one or two sentences of zoomed-out encouragement
}

Style guidelines for explanations:
- Use concrete descriptions like:
  - "You landed on the notes, but several onsets scooped upward."
  - "Stability was decent once settled, but a few transitions sagged before locking in."
- Mention both what is working and what isn’t, in the same sentence if possible.
- Avoid vague statements like "it was okay" or "pretty good."

Style guidelines for improvements:
- Always suggest at least ONE specific, actionable exercise.
- Good examples:
  - "Practice the phrase slowly against a piano and focus on landing directly on the pitch instead of sliding."
  - "Try a pitch-matching exercise: play a note, hum it back on 'ng', and hold it steady until it feels locked in."
  - "Use long 'sss' or 'vv' exhalations to train steady airflow, then apply that feeling to simple scales."
- Make exercises sound doable in a bedroom or living room. No special gear beyond maybe a piano app or tuner.

Tone:
- Honest and specific, like a real coach sitting next to them.
- No sugarcoating the scores, but never insulting.
- Always end with 'summary_encouragement' that frames this take as a snapshot on a journey, not a verdict.
- Do NOT include any extra keys or text outside of the JSON object.
"""

# The rest of the code (including get_chatgpt_feedback) remains unchanged,
# but ensure get_chatgpt_feedback uses SYSTEM_PROMPT as system message,
# and returns SAMPLE_FEEDBACK when mock=True or API unavailable.
