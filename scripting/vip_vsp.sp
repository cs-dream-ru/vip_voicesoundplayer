#pragma semicolon 1
#pragma newdecls required

#include <sdktools>
#include <clientprefs>

#include <vip_core>
#include <multicolors>
#include <soundlib>

enum struct Sound
{
	// Название звука в меню
	char name[128];

	// Путь к звуку
	char path[PLATFORM_MAX_PATH];

	// Название звука в чате
	// Если не прописан в конфиге, то в чат будет писаться название из меню
	char text[128];

	// Длительность звука
	float length;
}

bool 
	g_bEnabled[MAXPLAYERS+1],
	g_bLate;

int
	g_iStartSound,
	g_iEndSound,
	g_iLastUsedSound[MAXPLAYERS + 1];

Cookie g_hCookie;
ConVar vsp_sound_delay;
ArrayList g_hSoundList;

public Plugin myinfo =
{
	name = "[VIP] Voice Sound Player",
	author = "Danyas & who",
	version = "1.0.0"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	g_bLate = bLate;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("vip_core.phrases.txt");
	LoadTranslations("vip_vsp.phrases.txt");

	g_hSoundList = new ArrayList(sizeof Sound);

	g_hCookie = RegClientCookie("vsp_enabled", "", CookieAccess_Private);

	vsp_sound_delay = CreateConVar("vsp_sound_delay", "30.0", "Через N секунд можно будет включить новый звук", _, true, 0.0, true, 60.0);

	HookEvent("round_start", Event_Rounds);
	HookEvent("round_end", Event_Rounds);

	RegConsoleCmd("sm_snd", Command_Menu);
	RegConsoleCmd("sm_offsnd", Command_DisableSound);

	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}
}

public void Event_Rounds(Event event, const char[] name, bool dontBroadcast)
{
	g_iEndSound = GetTime();
}

public void OnMapStart()
{
	g_hSoundList.Clear();
	LoadSoundsConfig();
}

public void VIP_OnVIPLoaded()
{
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

public bool OnSelectItem(int client, const char[] sFeatureName)
{
	ShowMenu(client);

	return false;
}

public void OnClientPutInServer(int client)
{
	g_iLastUsedSound[client] = 0;
}

public void OnClientCookiesCached(int client)
{
	char cookie[32];
	GetClientCookie(client, g_hCookie, cookie, sizeof cookie);

	if(cookie[0])
	{
		g_bEnabled[client] = !!StringToInt(cookie);
	}
	else
	{
		g_bEnabled[client] = true;
		SetClientCookie(client, g_hCookie, "1");
	}
}

public Action Command_DisableSound(int client, int args)
{
	if(!client)
	{
		return Plugin_Handled;
	}

	g_bEnabled[client] = !g_bEnabled[client];
	SetClientCookie(client, g_hCookie, g_bEnabled[client] ? "1" : "0");

	CPrintToChat(client, "%T", g_bEnabled[client] ? "Enable" : "Disable", client);

	return Plugin_Handled;
}

public Action Command_Menu(int client, int args)
{
	if(!client)
	{
		return Plugin_Handled;
	}

	if(VIP_GetClientFeatureStatus(client, "VoiceSoundPlayer") == NO_ACCESS)
	{
		CPrintToChat(client, "%T", "NO_ACCESS", client);
		return Plugin_Handled;
	}

	ShowMenu(client);

	return Plugin_Handled;
}

void ShowMenu(int client)
{
	Menu menu = new Menu(Handler_Menu);

	menu.SetTitle("%T\n ", "Menu_Title", client);

	Sound sound;

	for (int i = 0; i < g_hSoundList.Length; i++)
	{
		g_hSoundList.GetArray(i, sound);
		
		if(!sound.name[0])
		{
			continue;
		}

		menu.AddItem(NULL_STRING, sound.name);			
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Menu(Menu menu, MenuAction action, int param, int param2)
{
	if(action == MenuAction_Select)
	{
		int iCurrentTime = GetTime();

		if(iCurrentTime >= g_iStartSound && iCurrentTime < g_iEndSound)
		{
			CPrintToChat(param, "%T", "SoundIsPlaying", param);
			return 0;
		}

		float delay = vsp_sound_delay.FloatValue;

		if(iCurrentTime - g_iLastUsedSound[param] < delay)
		{
			CPrintToChat(param, "%T", "Wait", param, delay - (iCurrentTime - g_iLastUsedSound[param]));
			return 0;
		}

		Sound sound;
		g_hSoundList.GetArray(param2, sound);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i)) 
			{
				if(g_bEnabled[i])
				{
					EmitSoundToClient(i, sound.path);
				}

				CPrintToChat(i, "%T", "Play", i, param, sound.text[0] ? sound.text : sound.name);	
			}
		}

		g_iLastUsedSound[param] = iCurrentTime + RoundToNearest(sound.length);
		g_iStartSound = iCurrentTime;
		g_iEndSound = g_iStartSound + RoundToNearest(sound.length);

		Command_Menu(param, 0);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void LoadSoundsConfig()
{
	char buffer[128];
	BuildPath(Path_SM, buffer, sizeof buffer, "data/vip/modules/vsp.ini");

	KeyValues kv = new KeyValues("Sound");

	if(!kv.ImportFromFile(buffer))
	{
		SetFailState("Конфиг %s отсутствует", buffer);
	}

	kv.Rewind();

	if(kv.GotoFirstSubKey())
	{
		Handle hSoundFile;
		int i = 0;

		Sound sound;

		do
		{
			kv.GetString("menu", sound.name, sizeof Sound::name);
			kv.GetString("path", sound.path, sizeof Sound::path);
			kv.GetString("text", sound.text, sizeof Sound::text);

			if(sound.path[0])
			{
				PrecacheSound(sound.path);
	
				Format(buffer, sizeof buffer, "sound/%s", sound.path);
				AddFileToDownloadsTable(buffer);

				hSoundFile = OpenSoundFile(sound.path);
	
				if(hSoundFile == INVALID_HANDLE)
				{
					continue;
				}
	
				sound.length = GetSoundLengthFloat(hSoundFile);
	
				g_hSoundList.PushArray(sound, sizeof sound);
	
				delete hSoundFile;
			}

			i++;
		} while(kv.GotoNextKey());
	}

	delete kv;
}
