#pragma once

// CompuSar local definition of the parts available of the mutex header

namespace std {

template<typename Mutex>
class unique_lock {
    Mutex *mutex = nullptr;
    bool  owned = false;

public:
    unique_lock() noexcept = default;
    explicit unique_lock(Mutex &mutex_object) : mutex( &mutex_object ) {
        lock();
    }

    unique_lock(const unique_lock &) = delete;
    unique_lock &operator=(const unique_lock &) = delete;

    unique_lock(unique_lock &&that) noexcept : mutex( that.mutex ), owned( that.owned ) {
        that.owned = false;
    }
    unique_lock &operator=(unique_lock that) {
        std::swap( mutex, that.mutex );
        std::swap( owned, that.owned );
    }

    ~unique_lock() {
        if( owned )
            unlock();
    }

    void lock() {
        assertWithMessage( mutex!=nullptr, "Attempted to lock an empty object" );
        assertWithMessage( !owned, "Attempted to lock an already owned mutex" );

        mutex->lock();
        owned = true;
    }

    void unlock() {
        assertWithMessage( owned, "Attempted to unlock a non-owned object" );
        owned = false;
        mutex->unlock();
    }
};

} // namespace std
