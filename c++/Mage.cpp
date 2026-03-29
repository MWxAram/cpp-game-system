#include "Mage.h"

// Конструктор
Mage::Mage(float startHP) : Player(startHP) {
    std::cout << "Маг рождается!" << std::endl;
    InitSpells(); 
    std::cout << "Маг обучен заклинаниям!" << std::endl;
}

void Mage::InitSpells() {
    // 3-символьные с эффектами
    spellBook["ttt"] = {"УДАР МЕТЕОРА", 50.0f, 80.0f, Color::Magenta, EffectType::BURN, 3}; // Поджог на 3 хода
    spellBook["qqw"] = {"ГРОМОВОЙ МОЛОТ", 40.0f, 60.0f, Color::Blue, EffectType::STUN, 1}; // Оглушение на 1 ход
    
    // Остальные без эффектов
    spellBook["qq"]  = {"МАГИЧЕСКИЙ ВЗРЫВ", 30.0f, 50.0f, Color::Cyan, EffectType::NONE, 0};
    spellBook["ty"]  = {"ДВОЙНОЙ УДАР", 20.0f, 30.0f, Color::Yellow, EffectType::NONE, 0};
    spellBook["f"]   = {"ОГНЕННАЯ ВСПЫШКА", 5.0f, 10.0f, Color::Red, EffectType::NONE, 0};
}

// Деструктор
Mage::~Mage() {
    std::cout << "[System]: Магический объект уничтожен." << std::endl;
}

void Mage::ModifyMana(float amount) {
    std::lock_guard<std::mutex> lock(manaMutex);
    mana += amount;
    if (mana > GetStartMana()) mana = GetStartMana();
    if (mana < 0) mana = 0;
}

float Mage::TryAbsorbDamage(float damage) {
    std::lock_guard<std::mutex> lock(manaMutex);
    if (mana >= damage) {
        mana -= damage;
        return 0;
    } else {
        float remaining = damage - mana;
        mana = 0;
        return remaining;
    }
}

float Mage::GetManaSafe() {
    std::lock_guard<std::mutex> lock(manaMutex);
    return mana;
}

void Mage::CastSpell(float magic) {
    ModifyMana(-magic);
    std::cout << "Заклинание сотворено!" << std::endl;
}

void Mage::TakeDamage(float damage) {
    float damageAfterShield = TryAbsorbDamage(damage);
    float currentMana = GetManaSafe();

    if(damageAfterShield <= 0){
        std::cout << Color::Blue << "Щит мага поглотил ВЕСЬ урон! Мана: " << currentMana << Color::Reset << std::endl;
    } else {
        std::cout << Color::Blue << "Щит сломан! " << damageAfterShield << " Урон наносится здоровью! Мана: " << currentMana << Color::Reset << std::endl;
        Player::TakeDamage(damageAfterShield); 
    }
}

void Mage::Attack(Player* target) {
    float bonus = Random(0.0f, 10.0f);
    float damage = spellPower + bonus;

    // Крит для мага (тоже 10%)
    if (std::rand() % 100 < 10) {
        damage *= 2.0f;
        std::cout << Color::Red << "!!! Критический удар !!! " << Color::Reset;
    }

    std::cout << Color::Red << "[Combat]: Огненый шар! " << damage << Color::Reset << std::endl;
    target->TakeDamage(damage);
}

void Mage::RegenMana(float amount) {
    ModifyMana(amount);
}

// Возвращает true, если заклинание сработало
// Улучшенный ProcessSpell с поиском по окончанию строки
bool Mage::ProcessSpell(std::string keyCombo, float manaCost, float damage, std::string spellName, Player* target) {
    // Проверяем, заканчивается ли буфер на нужную нам комбинацию
    if (comboBuffer.length() >= keyCombo.length()) {
        // Берем хвост буфера длиной с наше комбо
        std::string tail = comboBuffer.substr(comboBuffer.length() - keyCombo.length());
        
        if (tail == keyCombo) {
            float currentMana = GetManaSafe();

            if (currentMana >= manaCost) {
                std::cout << Color::Cyan << "\n[SPELL]: " << spellName << " !!!" << Color::Reset << std::endl;
                ModifyMana(-manaCost);
                target->TakeDamage(damage);

                
                comboBuffer = ""; // Очищаем всё после успеха
                return true;
            } else {
                std::cout << Color::Red << "\n[System]: Количество маны не хватает " << spellName << Color::Reset << std::endl;
                comboBuffer = "";
                return false;
            }
        }
    }
    return false;
}

void Mage::CheckCombo(Player* target) {
    // Проходим по всей книге заклинаний
    for (auto const& [combo, info] : spellBook) {
        // Проверяем, совпадает ли хвост буфера с каким-то комбо из книги
        if (comboBuffer.length() >= combo.length()) {
            std::string tail = comboBuffer.substr(comboBuffer.length() - combo.length());
            
            if (tail == combo) {
                if (GetManaSafe() >= info.manaCost) {
                    std::cout << info.colorCode << "\n\n!!! " << info.name << " !!!" << Color::Reset << std::endl;
                    ModifyMana(-info.manaCost);
                    target->TakeDamage(info.damage);
                    target->ApplyEffect(info.effect, info.effectDuration);
                    comboBuffer = ""; // Успех! Очищаем.
                    return;
                } else {
                    std::cout << Color::Red << "\n\n[Система]: Мало маны для " << info.name << Color::Reset << std::endl;
                    comboBuffer = "";
                    return;
                }
            }
        }
    }
}

void Mage::AddToCombo(char key, Player* target) {
    // 1. Обработка Backspace (код 8)
    if (key == 8) { 
        if (!comboBuffer.empty()) {
            comboBuffer.pop_back(); // Удаляем последний символ
            std::cout << "\n\r" << Color::Cyan << "[Буфер Комбо]: " << comboBuffer << "     " << Color::Reset << std::flush;
        }
        return; // Выходим, чтобы не добавлять код бэкспейса как символ
    }

    // 2. Добавляем символ
    comboBuffer += key;
    
    // Держим буфер небольшим (например, 5 символов)
    if (comboBuffer.length() > 5) {
        comboBuffer.erase(0, 1);
        comboBuffer = ""; 
        std::cout << Color::Red << "\r[Буфер]: Очищен (ошибка ввода)      " << std::flush;
    }

    std::cout << "\n\r" << Color::Cyan << "[Буфер Комбо]: " << comboBuffer << "     " << Color::Reset << std::flush;
    
    CheckCombo(target);
}