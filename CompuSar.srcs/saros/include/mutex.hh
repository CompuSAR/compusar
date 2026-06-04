#pragma once

template<typename Lock>
class unique_lock {
    Lock *_lock = nullptr;
    bool _ownLocked = false;

public:
    unique_lock() = default;
    explicit unique_lock(Lock &lock) : _lock(&lock) {
        _lock->lock();
        _ownLocked = true;
    }
    unique_lock(const unique_lock &) = delete;
    unique_lock &operator=(const unique_lock &) = delete;
    unique_lock(unique_lock &&that) {
        _lock = that._lock;
        _ownLocked = that._ownLocked;
        that._lock = nullptr;
    }
    unique_lock &operator=(unique_lock &&that) {
        unique_lock tmp(std::move(that));
        swap(tmp);

        return *this;
    }

    ~unique_lock() {
        if( _ownLocked && _lock!=nullptr ) {
            unlock();
        }
    }

    void lock() {
        assert(_lock);
        assert(!_ownLocked);

        _lock->lock();
        _ownLocked = true;
    }

    void unlock() {
        assert(_lock);
        assert(_ownLocked);

        _ownLocked = false;
        _lock->unlock();
    }
};
