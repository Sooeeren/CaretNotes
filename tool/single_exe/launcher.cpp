// Single-file CaretNotes for Windows.
//
// pack.exe appends the whole Release folder (compressed) to this launcher. On start
// the launcher unpacks it once to %LOCALAPPDATA%\CaretNotes\app\<build id>\ and runs
// caret_notes.exe from there, passing the command line through. Later starts of the
// same build reuse that folder; older builds' folders are removed.
//
// Payload layout (after the launcher's own bytes):
//   compressed blob | footer { u64 compressedSize, u64 rawSize, u64 id, char magic[8] }
// Blob (after LZMS decompression): "CNPK1" u32 count { u32 pathLen, utf8 path, u64 size, bytes }*

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <compressapi.h>
#include <shlwapi.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <iterator>
#include <string>
#include <vector>

static const char kMagic[8] = {'C', 'N', 'S', 'F', 'X', '0', '0', '1'};

#pragma pack(push, 1)
struct Footer {
  uint64_t compressedSize;
  uint64_t rawSize;
  uint64_t id;
  char magic[8];
};
#pragma pack(pop)

static void fail(const std::wstring& msg) {
  MessageBoxW(nullptr, msg.c_str(), L"CaretNotes", MB_ICONERROR | MB_OK);
  ExitProcess(1);
}

static std::wstring lastError() {
  wchar_t buf[512] = {0};
  FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr, GetLastError(), 0, buf, 512, nullptr);
  return buf;
}

static std::wstring widen(const std::string& s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

static bool exists(const std::wstring& p) { return GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES; }

static void makeDirs(const std::wstring& dir) {
  for (size_t i = 3; i <= dir.size(); i++) {
    if (i == dir.size() || dir[i] == L'\\') CreateDirectoryW(dir.substr(0, i).c_str(), nullptr);
  }
}

static void removeTree(const std::wstring& dir) {
  WIN32_FIND_DATAW fd;
  HANDLE h = FindFirstFileW((dir + L"\\*").c_str(), &fd);
  if (h != INVALID_HANDLE_VALUE) {
    do {
      std::wstring name = fd.cFileName;
      if (name == L"." || name == L"..") continue;
      std::wstring p = dir + L"\\" + name;
      if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        removeTree(p);
      } else {
        SetFileAttributesW(p.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(p.c_str());
      }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
  }
  RemoveDirectoryW(dir.c_str());
}

static std::vector<uint8_t> readPayload(const std::wstring& self, Footer& f) {
  HANDLE h = CreateFileW(self.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) fail(L"Could not read the program file: " + lastError());
  LARGE_INTEGER size;
  GetFileSizeEx(h, &size);
  DWORD got = 0;
  LARGE_INTEGER pos;
  pos.QuadPart = size.QuadPart - (LONGLONG)sizeof(Footer);
  if (pos.QuadPart < 0) fail(L"This program file is damaged (too small).");
  SetFilePointerEx(h, pos, nullptr, FILE_BEGIN);
  if (!ReadFile(h, &f, sizeof(Footer), &got, nullptr) || got != sizeof(Footer) || memcmp(f.magic, kMagic, 8) != 0) {
    fail(L"This program file is damaged or incomplete. Please download it again.");
  }
  pos.QuadPart = size.QuadPart - (LONGLONG)sizeof(Footer) - (LONGLONG)f.compressedSize;
  if (pos.QuadPart < 0) fail(L"This program file is damaged (bad size).");
  SetFilePointerEx(h, pos, nullptr, FILE_BEGIN);
  std::vector<uint8_t> data((size_t)f.compressedSize);
  size_t off = 0;
  while (off < data.size()) {
    DWORD chunk = (DWORD)std::min<size_t>(data.size() - off, 1 << 24);
    if (!ReadFile(h, data.data() + off, chunk, &got, nullptr) || got == 0) fail(L"Could not read the program file: " + lastError());
    off += got;
  }
  CloseHandle(h);
  return data;
}

static void unpack(const std::vector<uint8_t>& packed, const Footer& f, const std::wstring& dir) {
  DECOMPRESSOR_HANDLE d = nullptr;
  if (!CreateDecompressor(COMPRESS_ALGORITHM_LZMS, nullptr, &d)) fail(L"Could not start unpacking: " + lastError());
  std::vector<uint8_t> raw((size_t)f.rawSize);
  SIZE_T outSize = 0;
  if (!Decompress(d, packed.data(), packed.size(), raw.data(), raw.size(), &outSize) || outSize != raw.size()) {
    fail(L"Could not unpack CaretNotes: " + lastError());
  }
  CloseDecompressor(d);

  size_t p = 0;
  auto need = [&](size_t n) {
    if (p + n > raw.size()) fail(L"This program file is damaged (bad contents).");
  };
  need(9);
  if (memcmp(raw.data(), "CNPK1", 5) != 0) fail(L"This program file is damaged (bad header).");
  p = 5;
  uint32_t count;
  memcpy(&count, raw.data() + p, 4);
  p += 4;
  for (uint32_t i = 0; i < count; i++) {
    uint32_t len;
    need(4);
    memcpy(&len, raw.data() + p, 4);
    p += 4;
    need(len);
    std::wstring rel = widen(std::string((const char*)raw.data() + p, len));
    p += len;
    if (rel.find(L"..") != std::wstring::npos || (!rel.empty() && (rel[0] == L'\\' || rel[0] == L'/')) || rel.find(L':') != std::wstring::npos) {
      fail(L"This program file is damaged (bad path).");
    }
    for (auto& c : rel) if (c == L'/') c = L'\\';
    uint64_t size;
    need(8);
    memcpy(&size, raw.data() + p, 8);
    p += 8;
    need((size_t)size);
    std::wstring path = dir + L"\\" + rel;
    makeDirs(path.substr(0, path.find_last_of(L'\\')));
    HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) fail(L"Could not write " + path + L": " + lastError());
    size_t off = 0;
    while (off < size) {
      DWORD chunk = (DWORD)std::min<uint64_t>(size - off, 1 << 24), wrote = 0;
      if (!WriteFile(h, raw.data() + p + off, chunk, &wrote, nullptr)) fail(L"Could not write " + path + L": " + lastError());
      off += wrote;
    }
    CloseHandle(h);
    p += (size_t)size;
  }
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  wchar_t selfBuf[MAX_PATH * 4];
  DWORD n = GetModuleFileNameW(nullptr, selfBuf, (DWORD)std::size(selfBuf));
  if (n == 0 || n >= std::size(selfBuf)) fail(L"Could not find the program file.");
  std::wstring self(selfBuf, n);

  Footer f;
  std::vector<uint8_t> packed = readPayload(self, f);

  wchar_t local[MAX_PATH];
  DWORD ln = GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH);
  if (ln == 0 || ln >= MAX_PATH) fail(L"LOCALAPPDATA is not set.");
  std::wstring base = std::wstring(local) + L"\\CaretNotes\\app";
  wchar_t idHex[17];
  swprintf_s(idHex, L"%016llx", (unsigned long long)f.id);
  std::wstring dir = base + L"\\" + idHex;
  std::wstring done = dir + L"\\.unpacked";

  if (!exists(done)) {
    makeDirs(base);
    std::wstring tmp = base + L"\\tmp-" + std::to_wstring(GetCurrentProcessId());
    removeTree(tmp);
    makeDirs(tmp);
    unpack(packed, f, tmp);
    HANDLE m = CreateFileW((tmp + L"\\.unpacked").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
    if (m != INVALID_HANDLE_VALUE) CloseHandle(m);
    if (exists(dir) && !exists(done)) removeTree(dir);  // a half-unpacked folder from an interrupted start
    if (!MoveFileExW(tmp.c_str(), dir.c_str(), 0)) {
      // Another start of the same build won the race; use its folder.
      removeTree(tmp);
      if (!exists(done)) fail(L"Could not set up CaretNotes in " + dir + L": " + lastError());
    }
    // Drop folders of older builds (ones still in use just stay).
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW((base + L"\\*").c_str(), &fd);
    if (h != INVALID_HANDLE_VALUE) {
      do {
        std::wstring name = fd.cFileName;
        if (name == L"." || name == L".." || name == idHex || !(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (name.rfind(L"tmp-", 0) == 0) continue;
        removeTree(base + L"\\" + name);
      } while (FindNextFileW(h, &fd));
      FindClose(h);
    }
  }
  packed.clear();
  packed.shrink_to_fit();

  std::wstring exe = dir + L"\\caret_notes.exe";
  std::wstring cmd = L"\"" + exe + L"\" " + PathGetArgsW(GetCommandLineW());
  STARTUPINFOW si = {sizeof(si)};
  PROCESS_INFORMATION pi = {};
  if (!CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE, 0, nullptr, dir.c_str(), &si, &pi)) {
    fail(L"Could not start CaretNotes: " + lastError());
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 0;
}
