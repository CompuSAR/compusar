#pragma once

#include <cstdint>

class FixedString {
    const char *str_ = nullptr;

    explicit FixedString(const char *str) : str_(str) {}

public:
    FixedString() = default;
    FixedString(const FixedString &that) = default;
    FixedString &operator=(const FixedString &that) = default;
    FixedString(FixedString &&that) = delete;
    FixedString &operator=(FixedString &&that) = delete;

    const char *ptr() const { return str_; }
    operator const char *() const { return str_; }

    friend FixedString operator""_fs(const char *str, size_t);
};

inline FixedString operator""_fs(const char *str, size_t) {
    return FixedString{str};
}
