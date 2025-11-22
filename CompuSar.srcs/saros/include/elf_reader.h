#pragma once

namespace ElfReader {

typedef void (*EntryPoint)();

EntryPoint load_os();

} // namespace ElfReader
