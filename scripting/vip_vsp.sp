#pragma semicolon 1
#pragma newdecls required

#include <vip_core>
#include <emitsoundany>
#include <clientprefs>
#include <multicolors>
#include <soundlib>

#define CONFIG_PATH "data/vip/modules/vsp.ini"
#define MAX_SOUNDS 64

public Plugin myinfo = {
	name = "[VIP] Voice Sound Player",
	author = "Danyas (Rewrited by who2101)"
};

enum struct sound_t {
	char 	sName[128];			// Название звука в меню
	char 	sPath[128];			// Путь к звуку
	char 	sChatText[128];		// Название звука в чате
	float 	fLength;			// Длительность звука
	bool 	bAdmin;				// Звук будет доступен только ROOT админам
}

sound_t hSoundList[MAX_SOUNDS];

bool 
	g_bEnabled[MAXPLAYERS+1];

int iLastUsedSound[MAXPLAYERS + 1],
	iStartSound, iEndSound;

Handle gH_Cookie;

ConVar hSoundDelay;

public void OnPluginStart()
{
	LoadTranslations("vip_core.phrases.txt");
	LoadTranslations("vip_vsp.phrases.txt");

	gH_Cookie = RegClientCookie("vsp_enabled", "enabled cookies", CookieAccess_Protected);
	
	hSoundDelay = CreateConVar("vsp_sound_delay", "30.0");

	RegConsoleCmd("sm_snd", Command_Menu);
	RegConsoleCmd("sm_offsnd", Command_Disable);
	
	HookEvent("round_start", OnRoundEvent);
	HookEvent("round_end", OnRoundEvent);

	for(int i = 1; i <= MaxClients; i++)
		if(IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i))
			OnClientCookiesCached(i);
}

public void OnRoundEvent(Event event, const char[] name, bool dontBroadcast)
{
	iEndSound = GetTime();
}

public void OnMapStart() {
	char sBuff[192];
	
	LoadConfig();

	for (int i = 0; i < MAX_SOUNDS; i++)
	{
		if(hSoundList[i].sPath[0] == '\0')
			continue;

		PrecacheSoundAny(hSoundList[i].sPath);
		FormatEx(sBuff, sizeof(sBuff), "sound/%s", hSoundList[i].sPath);
		AddFileToDownloadsTable(sBuff);
	}
}

public void VIP_OnVIPLoaded() {
	VIP_RegisterFeature("VoiceSoundPlayer", BOOL, SELECTABLE, OnSelectItem, _, OnDrawItem);
}

public int OnDrawItem(int iClient, const char[] sFeatureName, int iStyle)
{
	switch(VIP_GetClientFeatureStatus(iClient, "VoiceSoundPlayer"))
	{
		case ENABLED: return ITEMDRAW_DEFAULT;
		case DISABLED: return ITEMDRAW_DISABLED;
		case NO_ACCESS: return ITEMDRAW_RAWLINE;
	}

	return iStyle;
}

public bool OnSelectItem(int client, const char[] sFeatureName) {
	ShowMenu(client);

	return false;
}

public void OnClientCookiesCached(int client) {
	iLastUsedSound[client] = 0;
	
	char cookie[32];
	GetClientCookie(client, gH_Cookie, cookie, sizeof(cookie));

	g_bEnabled[client] = cookie[0] == 0 ? true:!!StringToInt(cookie);

	if(!cookie[0])
	{
		SetClientCookie(client, gH_Cookie, "1");
	}
}

public Action Command_Disable(int client, int args) {
	g_bEnabled[client] = !g_bEnabled[client];
	SetClientCookie(client, gH_Cookie, g_bEnabled[client] ? "1":"0");

	CPrintToChat(client, "%T", g_bEnabled[client] ? "Enable" : "Disable", client);

	return Plugin_Handled;
}

void ShowMenu(int client) {
	Menu menu = new Menu(Menu_Handler);

	menu.SetTitle("%T\n ", "PhraseMenu", client);

	bool admin = CheckCommandAccess(client, NULL_STRING, ADMFLAG_ROOT, true);

	for (int i = 0; i < MAX_SOUNDS; i++) {
		if(hSoundList[i].sName[0] == '\0')
			continue;

		if(hSoundList[i].bAdmin && !admin)
			continue;

		char buff[8];
		IntToString(i, buff, sizeof(buff));
		menu.AddItem(buff, hSoundList[i].sName, hSoundList[i].sPath[0] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);			
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public Action Command_Menu(int client, int args) {
	if(!client)
		return Plugin_Handled;

	if(VIP_GetClientFeatureStatus(client, "VoiceSoundPlayer") == NO_ACCESS)
	{
		CPrintToChat(client, "%T", "NO_ACCESS", client);

		return Plugin_Handled;
	}

	ShowMenu(client);

	return Plugin_Handled;
}

public int Menu_Handler(Menu menu, MenuAction action, int param, int param2) {
	if(action == MenuAction_Select) {
		int currentTime = GetTime();
		
		if(currentTime >= iStartSound && currentTime < iEndSound)
		{
			CPrintToChat(param, "%T", "SoundIsPlaying", param);

			return 0;
		}
		
		if(currentTime - iLastUsedSound[param] < hSoundDelay.FloatValue)
		{
			CPrintToChat(param, "%T", "Wait", param, hSoundDelay.FloatValue - (currentTime - iLastUsedSound[param]));

			return 0;
		}

		char item[64];
		menu.GetItem(param2, item, sizeof(item));

		int iPos = StringToInt(item);

		for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i)) 
		{
			if(g_bEnabled[i])
			{
				EmitSoundToClientAny(i, hSoundList[iPos].sPath);
			}
				
			CPrintToChat(i, "%T", "Play", i, param, hSoundList[iPos].sChatText);
		}

		iLastUsedSound[param] = currentTime;
		iStartSound = currentTime;
		iEndSound = iStartSound + RoundToNearest(hSoundList[iPos].fLength);
		
		Command_Menu(param, 0);
	}
	if(action == MenuAction_End)
		delete menu;
		
	return 0;
}

void LoadConfig() {
	char Buffer[128];
	BuildPath(Path_SM, Buffer, sizeof(Buffer), CONFIG_PATH);

	KeyValues KvZc = new KeyValues("Sound");

	if(!KvZc.ImportFromFile(Buffer)) SetFailState("Конфиг %s отсутствует", Buffer);

	KvZc.Rewind();

	if(KvZc.GotoFirstSubKey())
	{
		Handle hSound;
		int i = 0;
		do {
			KvZc.GetSectionName(hSoundList[i].sName, sizeof(sound_t::sName));

			KvZc.GetString("path", hSoundList[i].sPath, sizeof(sound_t::sPath));
			KvZc.GetString("chat", hSoundList[i].sChatText, sizeof(sound_t::sChatText));
			
			if((hSound = OpenSoundFile(hSoundList[i].sPath)) != INVALID_HANDLE)
			{
				hSoundList[i].fLength = GetSoundLengthFloat(hSound);
				delete hSound;
			}
			
			hSoundList[i].bAdmin = !!KvZc.GetNum("admin", 0);
				
			i++;
		} while(KvZc.GotoNextKey());
	}

	delete KvZc;
}
