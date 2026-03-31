#pragma once

#include "saros/sync/signal.h"

#include <dma.h>
#include <ds/pool.h>
#include <saros/sync/mutex.h>

#include <stdint.h>

class SD {
public:
    enum class CardType { Uninit, Sdsc, Sdhc, Sdxc, Sduc, Inactive };
    static constexpr uint32_t BlockSize = 512;

    struct Block {
        alignas(DmaMemAlignment) std::array<uint8_t, BlockSize> data;
    };
    static_assert( sizeof(Block) == BlockSize );
    static_assert( alignof(Block) == DmaMemAlignment );

private:
    static constexpr size_t BlocksPoolSize = 128;
    static DS::PoolAllocator<Block, BlocksPoolSize> _blocksPool;

    mutable Saros::Sync::Mutex _dataLock;
    mutable Saros::Sync::Signal _dataIdle;
    Saros::Sync::Signal _cardStatusChanged;
    CardType _cardType = CardType::Uninit;
    uint64_t _numBlocks = 0;
    uint32_t _cardAddr = 0;

public:
    using BlockPtr = decltype(_blocksPool)::Ptr;

    SD() = default;
    SD(const SD &) = delete;
    const SD &operator=(const SD &) = delete;

    static void init();
    static void irq_handler_insert() noexcept;
    static void irq_handler_data() noexcept;

    explicit operator bool() const {
        return _cardType != CardType::Uninit;
    }

    size_t getNumBlocks() const {
        return _numBlocks;
    }

    [[nodiscard]] BlockPtr readBlock(uint32_t blockNum) const;
private:
    void threadMain() noexcept;

    void initCard();
    void uninit();

    [[nodiscard]] static bool isError(uint32_t status);
    [[nodiscard]] static bool isDataError(uint32_t status);
    [[nodiscard]] static bool isInserted();
    [[nodiscard]] bool checkUninit() const;
    void waitDataIdle() const;
};
