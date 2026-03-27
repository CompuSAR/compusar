#pragma once

#include "saros/sync/signal.h"

#include <stdint.h>

class SD {
public:
    enum class CardType { Uninit, Sdsc, Sdhc, Sdxc, Sduc, Inactive };

private:
    CardType _cardType = CardType::Uninit;
    Saros::Sync::Signal _cardStatusChanged;
    uint64_t _numBlocks = 0;
    uint32_t _cardAddr = 0;

public:
    SD() = default;
    SD(const SD &) = delete;
    const SD &operator=(const SD &) = delete;

    static void init();
    static void irq_handler() noexcept;

    explicit operator bool() const {
        return _cardType != CardType::Uninit;
    }

private:
    void threadMain() noexcept;

    void initCard();
    void uninit();

    [[nodiscard]] static bool isError(uint32_t status);
};
