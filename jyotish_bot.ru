#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import logging
from datetime import datetime
from telegram import Update, ReplyKeyboardRemove
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    ConversationHandler,
    ContextTypes,
    filters,
)
from geopy.geocoders import Nominatim
from timezonefinder import TimezoneFinder
import dashaflow

# ====================== ТОКЕН ======================
BOT_TOKEN = os.getenv("BOT_TOKEN")
# ===================================================

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Состояния диалога
NAME, DATE, TIME, CITY = range(4)

# Словари на русский
SIGN_RU = {
    "Aries": "Овен", "Taurus": "Телец", "Gemini": "Близнецы",
    "Cancer": "Рак", "Leo": "Лев", "Virgo": "Дева",
    "Libra": "Весы", "Scorpio": "Скорпион", "Sagittarius": "Стрелец",
    "Capricorn": "Козерог", "Aquarius": "Водолей", "Pisces": "Рыбы"
}

PLANET_RU = {
    "Sun": "Солнце", "Moon": "Луна", "Mars": "Марс",
    "Mercury": "Меркурий", "Jupiter": "Юпитер", "Venus": "Венера",
    "Saturn": "Сатурн", "Rahu": "Раху", "Ketu": "Кету"
}


def format_chart(name: str, chart: dict) -> str:
    lagna = chart["lagna"]
    planets = chart["planets"]
    dashas = chart.get("dashas", {})
    yogas = chart.get("yogas", [])

    text = f"🔮 *Натальная карта Джйотиш*\n"
    text += f"👤 *Имя:* {name}\n\n"

    # Лагна
    text += f"🌅 *Лагна (Асцендент):*\n"
    text += f"   Знак: *{SIGN_RU.get(lagna['sign'], lagna['sign'])}* ({lagna['degree']:.2f}°)\n"
    text += f"   Накшатра: {lagna['nakshatra']} (пада {lagna['pada']})\n\n"

    # Планеты
    text += "🪐 *Положения планет:*\n"
    for p_name, p_data in planets.items():
        ru_name = PLANET_RU.get(p_name, p_name)
        sign = SIGN_RU.get(p_data["sign"], p_data["sign"])
        house = p_data["house"]
        nak = p_data["nakshatra"]
        pada = p_data["pada"]
        dignity = p_data.get("dignity", "")
        retro = " ℞" if p_data.get("is_retrograde") else ""
        combust = " 🔥" if p_data.get("is_combust") else ""

        dig = f" ({dignity})" if dignity and dignity != "neutral" else ""
        text += f"   • *{ru_name}*{retro}{combust}: {sign} {p_data['degree']:.1f}° | дом {house} | {nak} ({pada}){dig}\n"

    text += "\n"

    # Текущая Махадаша
    if dashas and "maha" in dashas:
        maha = dashas["maha"]
        text += f"⏳ *Текущая Махадаша:* {PLANET_RU.get(maha['planet'], maha['planet'])}\n"
        text += f"   с {maha['start']} по {maha['end']}\n\n"

    # Йоги
    if yogas:
        text += "✨ *Найденные йоги:*\n"
        for y in yogas[:5]:
            text += f"   • {y['name']}: {y.get('description', '')}\n"
        if len(yogas) > 5:
            text += f"   ... и ещё {len(yogas)-5} йог\n"

    text += "\n_Расчёт выполнен по системе Лахири (Chitrapaksha ayanamsha)_"
    return text


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text(
        "Здравствуйте! Я помощник-бот астролога Алисы ✨\n\n"
        "Напишите, пожалуйста, *ваше имя*:",
        parse_mode="Markdown",
        reply_markup=ReplyKeyboardRemove()
    )
    return NAME


async def get_name(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["name"] = update.message.text.strip()
    await update.message.reply_text(
        f"Приятно познакомиться, *{context.user_data['name']}*!\n\n"
        "Теперь укажите *дату рождения* в формате ДД.ММ.ГГГГ\n"
        "Например: 15.04.1990",
        parse_mode="Markdown"
    )
    return DATE


async def get_date(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    text = update.message.text.strip()
    try:
        dt = datetime.strptime(text, "%d.%m.%Y")
        context.user_data["dob"] = dt.strftime("%Y-%m-%d")
        context.user_data["dob_display"] = text
    except ValueError:
        await update.message.reply_text(
            "❌ Неверный формат даты.\nПожалуйста, введите в формате *ДД.ММ.ГГГГ* (например 15.04.1990)",
            parse_mode="Markdown"
        )
        return DATE

    await update.message.reply_text(
        "Отлично! Теперь укажите *время рождения* в формате ЧЧ:ММ\n"
        "Например: 14:30\n\n"
        "Если точное время неизвестно — напишите 12:00",
        parse_mode="Markdown"
    )
    return TIME


async def get_time(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    text = update.message.text.strip()
    try:
        datetime.strptime(text, "%H:%M")
        context.user_data["tob"] = text
    except ValueError:
        await update.message.reply_text(
            "❌ Неверный формат времени.\nВведите в формате *ЧЧ:ММ* (например 14:30)",
            parse_mode="Markdown"
        )
        return TIME

    await update.message.reply_text(
        "Почти готово! Напишите *город рождения*\n"
        "(можно на русском или английском, например: Москва, Delhi, New York)",
        parse_mode="Markdown"
    )
    return CITY


async def get_city(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    city = update.message.text.strip()
    context.user_data["city"] = city

    msg = await update.message.reply_text("⏳ Ищу координаты города и рассчитываю натальную карту...")

    try:
        geolocator = Nominatim(user_agent="jyotish_alice_bot")
        location = geolocator.geocode(city, language="ru")

        if not location:
            await msg.edit_text(
                f"❌ Город «{city}» не найден.\nПопробуйте написать название по-другому или укажите более крупный населённый пункт."
            )
            return CITY

        lat = location.latitude
        lon = location.longitude

        tf = TimezoneFinder()
        tz = tf.timezone_at(lat=lat, lng=lon) or "UTC"

        chart = dashaflow.cast_chart(
            context.user_data["dob"],
            context.user_data["tob"],
            lat,
            lon,
            tz
        )

        report = format_chart(context.user_data["name"], chart)

        await msg.edit_text(
            f"✅ *Город найден:* {location.address}\n"
            f"📍 {lat:.4f}, {lon:.4f} | 🕒 {tz}\n\n"
            f"{report}",
            parse_mode="Markdown"
        )

        await update.message.reply_text(
            "Хотите рассчитать ещё одну карту? Нажмите /start"
        )

    except Exception as e:
        logger.exception("Ошибка расчёта")
        await msg.edit_text(
            f"❌ Произошла ошибка при расчёте:\n`{str(e)[:200]}`\n\n"
            "Попробуйте ещё раз /start",
            parse_mode="Markdown"
        )

    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text(
        "Диалог отменён. Чтобы начать заново — нажмите /start",
        reply_markup=ReplyKeyboardRemove()
    )
    return ConversationHandler.END


def main() -> None:
    if not BOT_TOKEN:
        print("Ошибка: не найден BOT_TOKEN")
        return

    application = Application.builder().token(BOT_TOKEN).build()

    conv_handler = ConversationHandler(
        entry_points=[CommandHandler("start", start)],
        states={
            NAME: [MessageHandler(filters.TEXT & \~filters.COMMAND, get_name)],
            DATE: [MessageHandler(filters.TEXT & \~filters.COMMAND, get_date)],
            TIME: [MessageHandler(filters.TEXT & \~filters.COMMAND, get_time)],
            CITY: [MessageHandler(filters.TEXT & \~filters.COMMAND, get_city)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    application.add_handler(conv_handler)
    application.add_handler(CommandHandler("cancel", cancel))

    print("Бот запущен...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
