#define WINAPI __attribute__((ms_abi))
#define CALLBACK __attribute__((ms_abi))

typedef int BOOL;
typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned long DWORD;
typedef long LONG;
typedef unsigned long ULONG;
typedef unsigned long long ULONG_PTR;
typedef void *HANDLE;
typedef void *HWND;
typedef HANDLE HKEY;
typedef void *HDEVINFO;
typedef DWORD ACCESS_MASK;
typedef ACCESS_MASK REGSAM;
typedef unsigned short WCHAR;
typedef const WCHAR *LPCWSTR;
typedef WCHAR *LPWSTR;
typedef BYTE *LPBYTE;
typedef DWORD *LPDWORD;

#define NULL ((void *)0)
#define TRUE 1
#define FALSE 0
#define INVALID_HANDLE_VALUE ((HANDLE)(ULONG_PTR) - 1)

typedef struct {
  DWORD Data1;
  WORD Data2;
  WORD Data3;
  BYTE Data4[8];
} GUID;

typedef struct {
  DWORD cbSize;
  GUID ClassGuid;
  DWORD DevInst;
  ULONG_PTR Reserved;
} SP_DEVINFO_DATA;
typedef SP_DEVINFO_DATA *PSP_DEVINFO_DATA;

BOOL WINAPI SetupDiClassGuidsFromNameW(LPCWSTR ClassName, GUID *ClassGuidList,
                                       DWORD ClassGuidListSize,
                                       DWORD *RequiredSize);
HDEVINFO WINAPI SetupDiGetClassDevsW(const GUID *ClassGuid, LPCWSTR Enumerator,
                                     HWND hwndParent, DWORD Flags);
BOOL WINAPI SetupDiEnumDeviceInfo(HDEVINFO DeviceInfoSet, DWORD MemberIndex,
                                  SP_DEVINFO_DATA *DeviceInfoData);
BOOL WINAPI SetupDiDestroyDeviceInfoList(HDEVINFO DeviceInfoSet);
BOOL WINAPI SetupDiGetDeviceRegistryPropertyW(
    HDEVINFO DeviceInfoSet, PSP_DEVINFO_DATA DeviceInfoData, DWORD Property,
    DWORD *PropertyRegDataType, BYTE *PropertyBuffer, DWORD PropertyBufferSize,
    DWORD *RequiredSize);
BOOL WINAPI SetupDiGetDeviceInstanceIdW(HDEVINFO DeviceInfoSet,
                                        PSP_DEVINFO_DATA DeviceInfoData,
                                        LPWSTR DeviceInstanceId,
                                        DWORD DeviceInstanceIdSize,
                                        DWORD *RequiredSize);
HKEY WINAPI SetupDiOpenDevRegKey(HDEVINFO DeviceInfoSet,
                                 PSP_DEVINFO_DATA DeviceInfoData, DWORD Scope,
                                 DWORD HwProfile, DWORD KeyType,
                                 REGSAM samDesired);

LONG WINAPI RegQueryValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD *lpReserved,
                             DWORD *lpType, BYTE *lpData, DWORD *lpcbData);
LONG WINAPI RegCloseKey(HKEY hKey);

LONG WINAPI CM_Get_Parent(DWORD *pdnDevInst, DWORD dnDevInst, ULONG ulFlags);
LONG WINAPI CM_Get_Device_IDW(DWORD dnDevInst, LPWSTR Buffer, ULONG BufferLen,
                              ULONG ulFlags);
DWORD WINAPI CM_MapCrToWin32Err(DWORD CmReturnCode, DWORD DefaultErr);