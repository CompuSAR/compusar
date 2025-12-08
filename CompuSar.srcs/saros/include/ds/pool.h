#pragma once

#include <abort.h>

#include <array>
#include <cstddef>
#include <memory>
#include <span>

namespace DS {

template <typename T, size_t NumElements>
struct PoolAllocatorData {
    static constexpr size_t ElementSize = sizeof(T);
    static constexpr size_t ElementAlignment = alignof(T);
    
    union PoolElement {
        alignas(ElementAlignment) std::byte element[ElementSize];
        PoolElement *next;
    };
    static_assert( offsetof(PoolElement, element)==0 );

    std::array<PoolElement, NumElements> pool;
};

template <typename T>
struct PoolAllocatorData<T, 0> {
    static constexpr size_t ElementSize = sizeof(T);
    static constexpr size_t ElementAlignment = alignof(T);
    
    union PoolElement {
        alignas(ElementAlignment) std::byte element[ElementSize];
        PoolElement *next;
    };
    static_assert( offsetof(PoolElement, element)==0 );

    std::span<PoolElement> pool;
};

template <typename T, size_t NumElements>
class PoolAllocator {
    PoolAllocatorData<T, NumElements> _pool;

    using PoolElement = decltype(_pool)::PoolElement;
    PoolElement *_firstFree;
public:

    using Ptr = std::unique_ptr<T, PoolAllocator&>;

    PoolAllocator() requires (NumElements != 0) : _firstFree(&_pool.pool[0]) {

        // Add all elements to the free list
        for( auto &element : _pool.pool ) {
            element.next = (&element)+1;
        }

        last()->next = nullptr;
    }

    explicit PoolAllocator(std::span<T> elements) requires (NumElements == 0)
    {
        assertWithMessage( elements.size() != 0, "Allocator got an empty pool" );

        _pool.pool = std::span<PoolElement>( convert(&elements[0]), elements.size() );
        _firstFree = &_pool.pool[0];

        // Add all elements to the free list
        for( auto &element : _pool.pool ) {
            element.next = (&element)+1;
        }

        last()->next = nullptr;
    }

    PoolAllocator(const PoolAllocator &) = delete;
    PoolAllocator &operator=(const PoolAllocator &) = delete;

    ~PoolAllocator() {
        abortWithMessage("PoolAllocator destructor called");
    }

    template <typename... Args>
    [[nodiscard]] Ptr alloc(Args&&... args) {
        checkWithMessage( _firstFree!=nullptr, "alloc called on empty pool" );

        std::byte *retVal = _firstFree->element;
        _firstFree = _firstFree->next;

        return Ptr( new (retVal) T(std::forward<Args>(args)...), *this );
    }

    void operator()(T *ptr) { // Deleter implmenetation
        free(ptr);
    }

    void free( T *element ) {
        PoolElement *poolElement = convert(element);
        assertWithMessage(
                poolElement >= &_pool.pool[0] && poolElement <= last(),
                "Attempt at freeing pointer from another pool");

        poolElement->next = _firstFree;
        _firstFree = poolElement;
    }

private:
    static PoolElement *convert(void *ptr) {
        return reinterpret_cast<PoolElement *>( reinterpret_cast<std::byte *>(ptr) );
    }

    PoolElement *last() {
        if constexpr( NumElements==0 ) {
            return &_pool.pool.last(1)[0];
        } else {
            return &_pool.pool[NumElements-1];
        }
    }
};

} // namespace ds
