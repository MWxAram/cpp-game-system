#pragma once // Защита от повторного включения
#include <atomic>
#include <iostream>
#include <vector>
#include <string>
#include <ctime>
#include <cstdlib>
#include <chrono>
#include <thread>
#include <future> // Для асинхронности
#include <windows.h>
#include <memory>
#include <fstream>
#include <mutex>
#include <map>

enum class EffectType { NONE, STUN, BURN, FREEZE };

// --- 1. ЦВЕТА И НАСТРОЙКИ ---
namespace Color {
    const std::string Red     = "\033[31m";
    const std::string Green   = "\033[32m";
    const std::string Blue    = "\033[34m";
    const std::string Cyan    = "\033[36m";
    const std::string Yellow  = "\033[33m";
    const std::string Reset   = "\033[0m";
    const std::string Magenta = "\033[35m";
}

// Для добавление в инвентарь предметов [Название, Вес, Цена]
struct Item {
    std::string name;
    int weight;
    int goldValue;
};


// --- 2. ГЛОБАЛЬНЫЕ ХЕЛПЕРЫ ---

//Для того чтобы на Mac и Windows можно было нажимать на конпик и код это видел и работал
#ifdef _WIN32
    #include <conio.h>
#else
    #include <termios.h>
    #include <unistd.h>
    #include <fcntl.h>
    #include <stdio.h> // Добавляем для stdin

    int _kbhit() {
        struct termios oldt, newt;
        int ch;
        int oldf;
        tcgetattr(STDIN_FILENO, &oldt);
        newt = oldt;
        newt.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &newt);
        oldf = fcntl(STDIN_FILENO, F_GETFL, 0);
        fcntl(STDIN_FILENO, F_SETFL, oldf | O_NONBLOCK);
        ch = getchar();
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
        fcntl(STDIN_FILENO, F_SETFL, oldf);
        if(ch != EOF) {
            ungetc(ch, stdin); // ИСПРАВЛЕНО: stdin вместо stdcin
            return 1;
        }
        return 0;
    }

    int _getch() {
        struct termios oldt, newt;
        int ch;
        tcgetattr(STDIN_FILENO, &oldt);
        newt = oldt;
        newt.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &newt);
        ch = getchar();
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
        return ch;
    }
#endif

extern std::atomic<bool> isGameRunning;

// Функция для получение рандомного числа
inline float Random(float min, float max) {
    return min + std::rand() % (int)(max - min + 1);
}

inline float ApplyPoison(float health) {
    while (health > 70.0f) {
        health -= 2.0f;
        std::cout << Color::Red << "Poison tick... Health: " << health << Color::Reset << std::endl;
    }
    return health;
}