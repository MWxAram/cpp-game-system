#pragma once
#include "Global.h"

class Player {
protected: // protected, чтобы Mage мог напрямую видеть эти данные
    float health = 100.0f;
    float currentWeight = 0.0f;
    int totalGoldValue = 0;
    int burnDuration = 0; // Сколько ходов осталось гореть
    float burnDamage = 5.0f; // Урон от огня за ход

public:
    Player(float startHP);
    virtual ~Player();

    std::vector<Item> inventory;

    // Геттеры
    float GetHealth() const { return health; }
    float GetWeight() const { return currentWeight; }

    // Методы
    void ApplyEffect(EffectType type, int duration); 
    void UpdateEffects();
    void Heal(float amount);
    virtual void TakeDamage(float damage);
    void AddItem(Item newItem);
    void Drop();

    
    // В Attack мы добавим шанс крита!
    virtual void Attack(Player* target);
};