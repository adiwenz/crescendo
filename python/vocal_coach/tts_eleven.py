from elevenlabs import ElevenLabs, save

client = ElevenLabs(api_key="YOUR_ELEVENLABS_KEY")

audio = client.generate(
    text="Welcome to your singing trainer app!",
    voice="Rachel",
    model="eleven_multilingual_v2"
)

save(audio, "tts_output.mp3")
print("Saved tts_output.mp3")