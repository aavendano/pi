import asyncio

from mistralai import agents


@agents.tool
async def get_current_time() -> dict[str, str]:
    """Current UTC time in ISO 8601. Use agents.now() so the value survives workflow replay."""
    return {"utc": agents.now().isoformat()}


agent = agents.Agent(
    model="mistral-large-4",
    name="chat-agent",
    instructions=(
        "You are a warm, concise conversational assistant. Keep replies short and natural, "
        "as in a chat. Remember what the user said earlier in this session and refer back to it. "
        "Ask at most one follow-up question when it genuinely helps, and never interrogate. "
        "If the user asks for the time, call get_current_time."
    ),
    tools=[get_current_time],
)


async def main() -> None:
    session = await agent.start_session()
    for message in ("Hi! Who are you?", "What time is it right now?"):
        state = await session.run(message)
        print(f"user: {message}\nagent: {state.text}\n")
    await session.cancel()


if __name__ == "__main__":
    asyncio.run(main())
