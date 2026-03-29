#include "Player.h"
#include "Global.h"
#include "Mage.h"


Player::Player(float startHP) : health(startHP) {
    std::cout << "[System]: Игрок рождается " << health << " HP." << std::endl;
}

Player::~Player() {
    std::cout << "[System]: Игрок уничтожен." << std::endl;
}

void Player::Heal(float amount) {
    health += amount;
    if (health > 100.0f) health = 100.0f;
    std::cout << Color::Green << "Исцелился для " << amount << ". Текущий HP: " << health << Color::Reset << std::endl;
}

void Player::TakeDamage(float damage) {
    float armor = 0.2f;
    float finalDamage = damage * (1.0f - armor);
    health -= finalDamage;
    if (health < 0) health = 0;
}

void Player::Attack(Player* target) {
    float damage = Random(10.0f, 25.0f);

    // --- ЛОГИКА КРИТИЧЕСКОГО УДАРА (10%) ---
    if (std::rand() % 100 < 10) { 
        damage *= 2.0f; // Удваиваем урон
        std::cout << Color::Red << "!!! Критический Удар !!! " << Color::Reset;
    }

    std::cout << "[Combat]: Игрок атакует! Урон: " << damage << std::endl;
    target->TakeDamage(damage);
}

    // Функция чтобы в инвентарь что-то добавить
void Player::AddItem(Item newItem) {
    inventory.push_back(newItem);
    currentWeight += static_cast<float>(newItem.weight);
    totalGoldValue += newItem.goldValue;
    std::cout << Color::Green << "[Log]: Добавлен " << newItem.name << " в инвентарь." << Color::Reset << std::endl;
}

    // Функция чтобы выбростить последнию вещь в инвентаре
void Player::Drop() {
    if (inventory.empty())
        return; 

    int lastIndex = static_cast<int>(inventory.size()) - 1;

    std::cout << Color::Cyan << "\n[!] ВНИМАНИЕ: Слишком тяжелый! (" << currentWeight << " KG)" << Color::Reset << std::endl;
    std::cout << Color::Cyan << "Удаляем последний элемент: " << inventory[lastIndex].name << " Вес: " << inventory[lastIndex].weight << Color::Reset << std::endl;

    currentWeight -= static_cast<float>(inventory[lastIndex].weight);
    inventory.pop_back();

    std::cout << "Новый вес: " << currentWeight << " KG" << std::endl;
}

void Player::ApplyEffect(EffectType type, int duration) {
    if (type == EffectType::BURN) {
        burnDuration = duration;
        std::cout << Color::Red << "[Эффект]: Воин загорелся на " << duration << " хода!" << Color::Reset << std::endl;
    }
}

void Player::UpdateEffects() {
    if (burnDuration > 0) {
        health -= burnDamage;
        std::cout << Color::Red << "[Огонь]: Горение наносит " << burnDamage 
                  << " урона воину! Осталось: " << health << " HP" << Color::Reset << std::endl;
        burnDuration--;
        
        // Даем игроку 0.8 секунды, чтобы осознать страдания воина
        std::this_thread::sleep_for(std::chrono::milliseconds(800)); 
    }
}
