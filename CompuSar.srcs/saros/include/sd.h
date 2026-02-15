#pragma once

#include "saros/sync/signal.h"

#include <stdint.h>

class SD {
    enum class CardType { Uninit, Sdsc, Sdhc, Sdxc, Sduc, Inactive } _cardType = CardType::Uninit;
    Saros::Sync::Signal _cardStatusChanged;

public:
    SD() = default;
    SD(const SD &) = delete;
    const SD &operator=(const SD &) = delete;

    static void init();
    static void irq_handler() noexcept;

private:
    void threadMain() noexcept;

    void initCard();
};
