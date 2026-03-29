#pragma once
#include "Global.h"
#include "Player.h"


struct Spell {
    std::string name;
    float manaCost;
    float damage;
    std::string colorCode; // Чтобы каждое заклинание могло иметь свой цвет
    EffectType effect;      // Тип эффекта
    int effectDuration;    // Длительность в ходах
};

class Mage : public Player {
private:
    std::map<std::string, Spell> spellBook;
    std::mutex manaMutex;
    float maxMana = 500.0f; // Максимум всегда 500
    float mana = 500.0f;
    float spellPower = 40.0f;
    std::string comboBuffer; // Хранилище нажатых клавиш


    // Приватные методы для внутреннего использования
    bool ProcessSpell(std::string keyCombo, float manaCost, float damage, std::string spellName, Player* target);
    void CheckCombo(Player* target);       // Внутренняя проверка: сложилось ли комбо?
    void ModifyMana(float amount);
    float TryAbsorbDamage(float damage);

public:
    Mage(float startHP);
    void InitSpells();
    virtual ~Mage();

    std::string GetComboBuffer() const { return comboBuffer; };
    float GetStartMana() const { return maxMana; }

    float GetManaSafe();
    void CastSpell(float magic);
    void RegenMana(float amount);
    void AddToCombo(char key, Player* target); // Метод, через который мы будем передавать кнопки
    
    // Переопределяем методы родителя
    void TakeDamage(float damage) override;
    void Attack(Player* target) override;
};