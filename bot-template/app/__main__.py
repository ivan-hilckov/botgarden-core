import asyncio
import logging
import os
from aiohttp import web
from aiogram import Bot, Dispatcher, types
from aiogram.webhook.aiohttp_server import SimpleRequestHandler, setup_application

# Configuration
BOT_TOKEN = os.getenv("BOT_TOKEN")
BOT_PORT = int(os.getenv("BOT_PORT", "8080"))
WEBHOOK_URL = os.getenv("WEBHOOK_URL")
BOT_NAME = os.getenv("BOT_NAME", "bot")

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize bot and dispatcher
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

@dp.message()
async def echo_handler(message: types.Message):
    """Simple echo handler"""
    await message.answer(f"🤖 Hello 111 from {BOT_NAME}! You said: {message.text}")

async def health_check(request):
    """Health check endpoint"""
    return web.Response(text="OK")

async def main():
    """Main application"""
    logger.info(f"Starting bot: {BOT_NAME}")
    
    # Create aiohttp application
    app = web.Application()
    
    # Add health check endpoint
    app.router.add_get("/health", health_check)
    
    # Setup webhook
    webhook_handler = SimpleRequestHandler(dispatcher=dp, bot=bot)
    webhook_handler.register(app, path="/webhook")
    setup_application(app, dp, bot=bot)
    
    # Set webhook
    if WEBHOOK_URL:
        await bot.set_webhook(url=WEBHOOK_URL, drop_pending_updates=True)
        logger.info(f"Webhook set to: {WEBHOOK_URL}")
    
    # Start server
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", BOT_PORT)
    await site.start()
    
    logger.info(f"Bot {BOT_NAME} started on port {BOT_PORT}")
    
    # Keep running
    try:
        await asyncio.Future()  # Run forever
    finally:
        await bot.session.close()

if __name__ == "__main__":
    asyncio.run(main())
