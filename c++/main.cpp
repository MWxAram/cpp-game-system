#include "Global.h"
#include "Player.h"
#include "Mage.h"


void SetCursor(int x, int y) {
    COORD coord;
    coord.X = x;
    coord.Y = y;
    SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), coord);
}


std::atomic<bool> isGameRunning(true);

void DrawHPLive(float current, float max, std::string color) {
    int barWidth = 15;
    float ratio = current / max;
    if (ratio < 0) ratio = 0;
    int pos = barWidth * ratio;

    std::cout << color << "[";
    for (int i = 0; i < barWidth; ++i) {
        if (i < pos) std::cout << "■";
        else std::cout << "-";
    }
    std::cout << "] " << (int)current << " HP" << Color::Reset;
}

// ________Функции для работы дуэлей________

// Функция для начала дуэли и по очереди их атаки
// Функция для дуэли (Классическая версия)
void StartDuel(Player* warrior, Mage* mage) {
        system("cls");
    while (warrior->GetHealth() > 0 && mage->GetHealth() > 0 && isGameRunning) {

        // --- ВЫВОД СТАТУСА ---
        std::cout << Color::Cyan << "========= БИТВА =========" << Color::Reset << std::endl;
        std::cout << "Воин HP: " << (int)warrior->GetHealth() << std::endl;
        std::cout << "Маг  HP: " << (int)mage->GetHealth() << " | Мана: " << (int)mage->GetManaSafe() << " / 500" << std::endl;
        std::cout << "=========================" << std::endl;
        std::cout << "Нажмите 'ESC' для выхода.\n" << std::endl;

        // 1. ХОД ВОИНА
        warrior->UpdateEffects(); // Тут выведется урон от огня, если он есть
        if (warrior->GetHealth() <= 0) break;

        warrior->Attack(mage);
        if (mage->GetHealth() <= 0) break;

        // 2. ХОД МАГА
        std::cout << "\n[Ваш ход!]: Вводите комбо. 'E' - закончить ход." << std::endl;
        
        bool turnOver = false;
        while (!turnOver && isGameRunning) {
            if (_kbhit()) {
                char key = _getch();

                if (key == 27) { // ESC
                    isGameRunning = false;
                } 
                else if (key == 'e' || key == 'E') {
                    turnOver = true;
                } 
                else {
                    mage->AddToCombo(key, warrior);

                    // Если заклинание вылетело — завершаем ход автоматически через секунду
                    if (mage->GetComboBuffer().empty()) {
                        std::this_thread::sleep_for(std::chrono::milliseconds(800));
                        turnOver = true;
                    }

                    if (warrior->GetHealth() <= 0) break;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        if (!isGameRunning) break;
    }

    // Финал битвы
    if (warrior->GetHealth() <= 0) std::cout << Color::Green << "ПОБЕДА МАГА!" << Color::Reset << std::endl;
    else if (mage->GetHealth() <= 0) std::cout << Color::Red << "ПОБЕДА ВОИНА!" << Color::Reset << std::endl;
    
    // Сохранение в файл
    std::ofstream saveFile("last_battle.txt");
    if (saveFile.is_open()) {
        saveFile << "Воин HP: " << warrior->GetHealth() << "\nМаг HP: " << mage->GetHealth() << std::endl;
        saveFile.close();
    }
}


// Функция для востоновление маны во время дуэли 5 раз подряд раз в 2 секунды
void BackgroundManaRegen(Mage* mage) {
    while (isGameRunning) { 
        std::this_thread::sleep_for(std::chrono::milliseconds(2000));
        if (mage->GetHealth() <= 0) break;

        if (mage->GetManaSafe() < mage->GetStartMana()) {
            mage->RegenMana(5.0f);
            // НИКАКИХ cout здесь! StartDuel сам всё покажет.
        }
    }
}

// Сама наша игра запускается здесь
int main() {

    SetConsoleOutputCP(65001);
    // Во время запуска получаем время для функции рандома
    std::srand(std::time(nullptr));

// Теперь это "Умные" объекты. Они сами удалятся из памяти.
    auto warrior = std::make_unique<Player>(120.0f);
    auto mage = std::make_unique<Mage>(80.0f);

    // Наносим классу воин 30 урона
    
    // std::cout << "\n--- Warrior turn ---" << std::endl;
    // myWarrior.TakeDamage(30.0f);

    // Классу маг увиличиваем силу магии,наносим ему урон 10, добавляем в его инвентарь предмет с весом и ценой
    
    // std::cout << "\n--- Mage turn ---" << std::endl;
    // myMage.CastSpell(15.0f);              // Уникальное умение мага
    // myMage.TakeDamage(10.0f);                // Умение, доставшееся от родителя Player
    // myMage.AddItem({"Old Wand", 2, 150}); // Инвентарь тоже работает!

    // Добавляем предмет в инвентарь воина
    
    // myWarrior.AddItem({"Steel Axe", 5, 80});

    // Считаем сколько в общем у него золота и вес в его инвентаре 
    
    // std::cout << "\n--- Inventory Details ---" << std::endl;
    // for (int i = 0; i < myWarrior.inventory.size(); i++) {
    //     // Выводим имя и цену, обращаясь через точку .
    //     std::cout << "Slot " << i << ": " << myWarrior.inventory[i].name
    //               << " | Worth: " << myWarrior.inventory[i].goldValue << " gold"
    //               << " | Weight: " << myWarrior.inventory[i].weight << " KG" << std::endl;
    // }



    // Для работы многопоточных задач в данном случее для регена маны
    auto futureRegen = std::async(std::launch::async, BackgroundManaRegen, mage.get());

    // Начала дуэли
    StartDuel(warrior.get(), mage.get());


    // Завершение работы
    isGameRunning = false;
    return 0;
}