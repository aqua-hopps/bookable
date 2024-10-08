#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>
#include <dbi>
#include <morecolors>

#define NAME_LENGTH 16
#define IP_LENGTH 16
#define PASSWORD_LENGTH 10

#define MAX_AFK_PLAYERS 2
#define MAX_AFK_TIME 600.0
#define MAX_SDR_RETRIES 10

public Plugin myinfo =
{
    name = "Matcha Bookable",
    author = "aqua-hopps & avan",
    description = "A plugin for sending server info to a database.",
    version = "1.35",
    url = "https://github.com/aqua-hopps/bookable"
};

char g_dbName[NAME_LENGTH];
char g_instanceName[NAME_LENGTH];
char g_serverPassword[PASSWORD_LENGTH + 1];
char g_rconPassword[PASSWORD_LENGTH + 1];
char g_publicIP[16];
char g_fakeIP[16];

int g_publicPort;
int g_fakePort;
int g_tvPort;
int g_playerCount;

Address g_adrFakeIP;
Address g_adrFakePorts;

ConVar g_cvarDBName;
ConVar g_cvarServerPassword;
ConVar g_cvarRconPassword;

Handle g_hGameConf;
Handle g_hAFKTimer;


public void OnPluginStart(){
    // Create ConVars
    g_cvarDBName = CreateConVar("sm_bookable_database", "", "Set the database keyname.");
    g_cvarServerPassword = FindConVar("sv_password");
    g_cvarRconPassword = FindConVar("rcon_password");

    // For SDR command
    RegConsoleCmd("sm_sdr", Command_sdrRequest, "Request SDR IP");

    // Hook database name
    HookConVarChange(g_cvarDBName, OnDBNameChanged);

    // Set random passwords
    GetRandomString(g_serverPassword, PASSWORD_LENGTH);
    GetRandomString(g_rconPassword, PASSWORD_LENGTH);
    g_cvarServerPassword.SetString(g_serverPassword);
    g_cvarRconPassword.SetString(g_rconPassword);

    // Load gamedata
    g_hGameConf = LoadGameConfigFile("bookable");

    // Get addresses for engine variables
    g_adrFakeIP = GameConfGetAddress(g_hGameConf, "g_nFakeIP");
    g_adrFakePorts = GameConfGetAddress(g_hGameConf, "g_arFakePorts");

    // Get server information
    g_cvarDBName.GetString(g_dbName, sizeof(g_dbName));
    g_publicPort = GetConVarInt(FindConVar("hostport"));
    g_tvPort = GetConVarInt(FindConVar("tv_port"));
    GetPublicIP(g_publicIP, sizeof(g_publicIP));
    GetFakeIP(g_fakeIP, sizeof(g_fakeIP));
    g_fakePort = GetFakePort(0);

    // If the plugin is manually loaded
    if (g_dbName[0] != '\0' && SQL_CheckConfig(g_dbName)){
        Database.Connect(SendServerInfoAll, g_dbName, _);
    }
}

public void OnClientConnected(){
    g_playerCount++;
    SetAFKTimer();
}

public void OnClientDisconnect(){
    g_playerCount--;
    SetAFKTimer();
}

public void OnDBNameChanged(ConVar convar, const char[] oldValue, const char[] newValue){
    strcopy(g_dbName, sizeof(g_dbName), newValue);
    // If the plugin is loaded on server start
    CreateTimer(5.0, WaitForSteamInfo, 0, TIMER_REPEAT);
}

public Action Command_sdrRequest(int client, int args) {
    // Usually sv_password value wouldn't be modified so no need to update it
    CPrintToChat(client, "{aqua}connect %s:%d; password \"%s\"", g_fakeIP, g_fakePort, g_serverPassword);
    return Plugin_Handled;
}

public Action WaitForSteamInfo(Handle timer, int retry){
    if (g_adrFakeIP && g_adrFakePorts && GetPublicIP(g_publicIP, sizeof(g_publicIP))){
        GetFakeIP(g_fakeIP, sizeof(g_fakeIP));
        g_fakePort = GetFakePort(0);

        // Check if keyname is in databases.cfg
        if (!SQL_CheckConfig(g_dbName)){
            ThrowError("Could not locate \"%s\" in databases.cfg.", g_dbName);
        }
        else {
            Database.Connect(SendServerInfoAll, g_dbName, _);
        }
        
        return Plugin_Stop;
    }
    else if (retry == MAX_SDR_RETRIES){
        // Check if keyname is in databases.cfg
        if (!SQL_CheckConfig(g_dbName)){
            ThrowError("Could not locate \"%s\" in databases.cfg.", g_dbName);
        }
        else {
            Database.Connect(SendServerInfoAll, g_dbName, _);
        }
        
        return Plugin_Stop;
    }
    else{
        retry++;
        return Plugin_Continue;
    }
}

public Action OnServerEmpty(Handle timer){
    Database.Connect(SendServerInfoEmpty, g_dbName, _);
    g_hAFKTimer = INVALID_HANDLE; // Destroy timer
    return Plugin_Stop;
}

public void SendServerInfoAll(Database db, const char[] error, any data){
    if (db == null){
        LogError("Could not connect to the database: %s", error);
    }
    else{
        // Check if the server is a GCP instance
        char buffer[256];
        db.Format(buffer, sizeof(buffer), "SELECT instance_name FROM booked WHERE `ip` = '%s' ;", g_publicIP);
        db.Query(T_SendServerInfoAll, buffer, _);

        // Count current players in the server
        g_playerCount = GetPlayerCount();
        SetAFKTimer();
    }
}

public void SendServerInfoEmpty(Database db, const char[] error, any data){
    if (db == null){
        LogError("Could not connect to the database: %s", error);
    }
    else{
        char buffer[256];
        if (g_instanceName[0] == '\0'){
            db.Format(buffer, sizeof(buffer), "UPDATE booked SET `afk` = 1	\
                WHERE `ip` = '%s' AND `port` = %d ;", g_publicIP, g_publicPort);
        }
        else {
            db.Format(buffer, sizeof(buffer), "UPDATE booked SET `afk` = 1 WHERE `instance_name` = '%s' ;", g_instanceName);
        }
        db.Query(T_SendServerInfo, buffer, _);
    }
}

public void SendServerPasswords(Database db, const char[] error, any data){
    if (db == null){
        LogError("Could not connect to the database: %s", error);
    }
    else{
        char buffer[256];
        if (g_instanceName[0] == '\0'){
            db.Format(buffer, sizeof(buffer),
                "UPDATE booked				\
                SET								\
                    `sv_password` 	= '%s'	,	\
                    `rcon_password` = '%s'		\
                WHERE							\
                    `ip` 	= '%s'		\
                AND								\
                    `port`	=  %d	;",	\
                g_serverPassword, g_rconPassword, g_publicIP, g_publicPort);
        }
        else {
            db.Format(buffer, sizeof(buffer),
                "UPDATE booked				\
                SET								\
                    `sv_password` 	= '%s'	,	\
                    `rcon_password` = '%s'		\
                WHERE							\
                    `instance_name`	= '%s'	;",	\
                g_serverPassword, g_rconPassword, g_instanceName);
        }
        db.Query(T_SendServerInfo, buffer, _);
    }
}

public void T_SendServerInfoAll(Database db, DBResultSet results, const char[] error, any data){
    if (db == null || results == null || error[0] != '\0'){
        LogError("Could not query the database: %s", error);
    }
    else if (results.RowCount == 0){
        LogError("This server has no entry in the database.");
    }
    else if (results.RowCount >= 1){
        char buffer[512];
        results.FetchRow();

        if(results.IsFieldNull(0)){
            g_instanceName[0] = '\0';
        }
        else{
            results.FetchString(0, g_instanceName, sizeof(g_instanceName));
        }

        if (g_instanceName[0] == '\0'){
            db.Format(buffer, sizeof(buffer),
                "UPDATE	booked					\
                SET									\
                    `sv_password`	=	'%s'	,	\
                    `rcon_password`	=	'%s'	,	\
                    `sdr_ip`		=	'%s'	,	\
                    `sdr_port`		=	 %d		,	\
                    `stv_port`	=	 %d		,	\
                    `status` = 'started'		\
                WHERE								\
                    `ip`	=		'%s'		\
                AND									\
                    `port`	=	 %d		;",	\
                g_serverPassword, g_rconPassword, g_fakeIP, g_fakePort, g_tvPort, g_publicIP, g_publicPort);
        }
        else{
            db.Format(buffer, sizeof(buffer),
                "UPDATE	booked					\
                SET									\
                    `sv_password`	=	'%s'	,	\
                    `rcon_password`	=	'%s'	,	\
                    `sdr_ip`		=	'%s'	,	\
                    `sdr_port`		=	 %d		,	\
                    `port`	=	 %d		,	\
                    `stv_port`	=	 %d		,	\
                    `status` = 'started'		\
                WHERE								\
                    `instance_name` = 	'%s'	;",	\
                g_serverPassword, g_rconPassword, g_fakeIP, g_fakePort, g_publicPort, g_tvPort, g_instanceName);
        }
        db.Query(T_SendServerInfo, buffer, _);
    }
}

public void T_SendServerInfo(Database db, DBResultSet results, const char[] error, any data){
    if (db == null || results == null || error[0] != '\0'){
        LogError("Could not send server info to the database: %s", error);
    }
    else if (results.AffectedRows > 1){
        LogError("This server has multiple entries in the database.");
    }
}

// Generate a random password
void GetRandomString(char[] buffer, int len){
    static char charList[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    
    for (int i = 0; i <= len; i++){
        // Using GetURandomInt is "safer" for random number generation
        char randomChar;
        do {
            randomChar = charList[GetURandomInt() % (sizeof(charList) - 1)];
        } while (IsCharInArray(randomChar, buffer, i));
        
        buffer[i] = randomChar;
    }

    // Strings need to be null-terminated
    buffer[len] = '\0';
}

// Check if a character is already present in an array
bool IsCharInArray(char c, char[] array, int size) {
    for (int i = 0; i < size; i++) {
        if (array[i] == c) {
            return true;
        }
    }
    return false;
}

int GetPlayerCount() {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            count++;
        }
    }
    return count;
}

void SetAFKTimer(){
    if (g_playerCount < MAX_AFK_PLAYERS && g_hAFKTimer == INVALID_HANDLE){
        // Start AFK timer when playercount is less or equal to the MAX_AFK_PLAYERS
        g_hAFKTimer = CreateTimer(MAX_AFK_TIME, OnServerEmpty, _);
    }
    if (g_playerCount >= MAX_AFK_PLAYERS && g_hAFKTimer != INVALID_HANDLE){
        // Delete timer when playercount exceeds MAX_AFK_PLAYERS
        CloseHandle(g_hAFKTimer);
        g_hAFKTimer = INVALID_HANDLE;
    }
}

bool GetPublicIP(char[] buffer, int size){
    int ipaddr[4];
    SteamWorks_GetPublicIP(ipaddr);

    if (ipaddr[0] != '\0'){
        Format(buffer, size, "%d.%d.%d.%d", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
        return true;
    }
    else{
        return false;
    }
}

void GetFakeIP(char[] buffer, int size){
    if (!g_adrFakeIP) {
        buffer[0] = '\0';
    }
    int ipaddr = LoadFromAddress(g_adrFakeIP, NumberType_Int32);

    int octet1 = (ipaddr >> 24) & 255;
    int octet2 = (ipaddr >> 16) & 255;
    int octet3 = (ipaddr >> 8) & 255;
    int octet4 = ipaddr & 255;

    Format(buffer, size, "%d.%d.%d.%d", octet1, octet2, octet3, octet4);
}

int GetFakePort(int num) {
    if (!g_adrFakePorts || num < 0 || num >= 2){
        return 0;
    }
    return LoadFromAddress(g_adrFakePorts + (num * 0x2), NumberType_Int16);
}
