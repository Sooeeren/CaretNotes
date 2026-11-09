// pack.exe <app folder> <launcher.exe> <out.exe>
// Appends the app folder, LZMS-compressed, to the launcher (format: see launcher.cpp).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <compressapi.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace fs = std::filesystem;

#pragma pack(push, 1)
struct Footer {
  uint64_t compressedSize;
  uint64_t rawSize;
  uint64_t id;
  char magic[8];
};
#pragma pack(pop)

static std::vector<uint8_t> readAll(const fs::path& p) {
  std::ifstream in(p, std::ios::binary);
  return std::vector<uint8_t>(std::istreambuf_iterator<char>(in), {});
}

template <typename T>
static void put(std::vector<uint8_t>& out, T v) {
  const uint8_t* b = reinterpret_cast<const uint8_t*>(&v);
  out.insert(out.end(), b, b + sizeof(T));
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 4) {
    fwprintf(stderr, L"usage: pack <app folder> <launcher.exe> <out.exe>\n");
    return 2;
  }
  fs::path src = argv[1];
  std::vector<fs::path> files;
  for (auto& e : fs::recursive_directory_iterator(src)) {
    if (e.is_regular_file()) files.push_back(e.path());
  }
  std::sort(files.begin(), files.end());

  std::vector<uint8_t> raw = {'C', 'N', 'P', 'K', '1'};
  put<uint32_t>(raw, (uint32_t)files.size());
  for (auto& f : files) {
    std::u8string rel = fs::relative(f, src).generic_u8string();
    put<uint32_t>(raw, (uint32_t)rel.size());
    raw.insert(raw.end(), rel.begin(), rel.end());
    auto data = readAll(f);
    put<uint64_t>(raw, (uint64_t)data.size());
    raw.insert(raw.end(), data.begin(), data.end());
  }

  COMPRESSOR_HANDLE c = nullptr;
  if (!CreateCompressor(COMPRESS_ALGORITHM_LZMS, nullptr, &c)) return fwprintf(stderr, L"CreateCompressor failed\n"), 1;
  SIZE_T need = 0;
  Compress(c, raw.data(), raw.size(), nullptr, 0, &need);
  std::vector<uint8_t> packed(need);
  SIZE_T got = 0;
  if (!Compress(c, raw.data(), raw.size(), packed.data(), packed.size(), &got)) return fwprintf(stderr, L"Compress failed %lu\n", GetLastError()), 1;
  packed.resize(got);
  CloseCompressor(c);

  // Build id: FNV-1a over the packed data, so every different build unpacks to its own folder.
  uint64_t id = 1469598103934665603ull;
  for (uint8_t b : packed) id = (id ^ b) * 1099511628211ull;

  auto stub = readAll(argv[2]);
  std::ofstream out(argv[3], std::ios::binary | std::ios::trunc);
  out.write((const char*)stub.data(), stub.size());
  out.write((const char*)packed.data(), packed.size());
  Footer f{packed.size(), raw.size(), id, {'C', 'N', 'S', 'F', 'X', '0', '0', '1'}};
  out.write((const char*)&f, sizeof f);
  out.close();
  wprintf(L"%zu files, %.1f MB -> %.1f MB\n", files.size(), raw.size() / 1048576.0, (stub.size() + packed.size()) / 1048576.0);
  return out ? 0 : 1;
}
