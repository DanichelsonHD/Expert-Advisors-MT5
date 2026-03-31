/* Strategy Evaluation Framework //////////////////////////////////
* Richard Edye / oP group Germany
* This file is part of the Zorro Project.
* Copyright (c) 2025 oP group Germany GmbH
* 
* You may use, modify, or share this code only for 
* personal and noncommercial purposes. Any commercial 
* use, resale, or distributing any part of this code, 
* or of variants or works based on it, in original, 
* translated, compiled or modified form, requires 
* permission from the copyright holder. 
* By using this code you agree to these usage terms.
*
* This code is distributed in the hope that it will be useful,
* but without any warranty; without even the implied warranty of
* merchantability or fitness for a particular purpose. 
*////////////////////////////////////////////////////////////////////

// Global //////////////////////////////////////////////////////
//#define _ASSETLIST "AssetsFix" // trade all assets from the list
//#define XMLJOBS	// Use XML job files; otherwise CSV
//#define AUTO_OPTIMIZE	// optimize variables by name 

#define EFVERSION	"1.10"
//#define CORETEST
//#define LOGNUMBER 2
//#define VERBOSE	7+DIAG
#define VARDATA		strf("#Data\\%s_vars.bin",RootName) // loads at start
#define VARCORE		strf("#Data\\%s_core.bin",RootName) // for the cores
#define VARALGO		strf("#Data\\%s_algo.bin",RootName) // for the algos
#define SYSLIST		"include\\evars.h"	// global variables 
#ifndef VARLIST
#ifdef _WIN32
#define VARLIST		strf("Strategy\\%s.cpp",RootName) // strategy variables
#else
#define VARLIST		strf("Strategy\\%s.c",RootName)
#endif
#endif

#define ZONE		CST // for Backtests 1..3 only
#define TRAINDEFAULT 1	// don't autodetect training
//#define TRAINCYCLES	1
//#define _ACCOUNT	100000
#define STEPDEFAULT	-25	// for optimized variables
#define PRF_LIMIT	1.25 // minimum profit factor for summary
#define R2_LIMIT	0.25 // minimum R2 for summary
#define CA_LIMIT	75	// minimum positive CA runs for algos

#define FIELDWIDTH	40
#define VARCOLOR	rgb(230,230,255)
DWORD ALGOCOLORS[5]	= { ORANGE,0xFFCC77,0xffee22,YELLOW,0xDD8844 };
#define GLOBALCOLOR	LIGHTBLUE 
#define ALLCOLOR	YELLOW
#define SYSCOLOR	SILVER
#define _MSG		TO_WINDOW


#define MAXALGOS	100	
#define MAXNAMES	101
#define MAXVARS		100
#define MAXJOBS		1000	
#define MAXCLUSTERS	100
#define MAXVSIZE	MAXVARS*sizeof(VTYPE)

#define N_ASSET	1
#define N_ALGO	2
#define N_TF	3
#define N_PRF	15	// Profit factor field number
#define N_R2	21
#define N_CA	22

///////////////////////////////////////////////////////////////
#ifndef NV
#define NO_VARS
#include <evars.h>
END_OF_VARS
#endif
#undef run

#ifdef _ASSETS
#define DO_VARIANTS
#endif
#ifdef _ALGOS
#define DO_VARIANTS
#endif
#ifdef _TIMEFRAMES
#define DO_VARIANTS
#endif

typedef struct {
	var Value,Start,End;
	var Step; // optimize when nonzero
	int Type; // +1 Optimize, +2 Algo specific, +8 by Job 
	char Name[44];
} VTYPE;

VTYPE Variables[MAXVARS];

/////////////////////////////////////////////////////////////////
int NumVars = 0,NumJobs = 0,NumAlgos = 0,NumClusters = 0,NumOptimized = 0,
	DoStart = 0,DoTrain = 0,ResetSlider = 0,
	JobMode = 0; // 2 = Profile, 3 = Matrix, 4,5 = Reality Check, +8 = Multiple Jobs
#define DO_CA	((JobMode&2) && NumClusters)
#define DO_MRC	(JobMode&4)
#define DO_JOBS	((JobMode&8) && NumJobs)

int N,i,j,k;
var* Values;

string Msg;
VTYPE* JobContents = 0;

char JobName[40],	// for log files and for name in summaries
	Summary[1024],	// summary path, also for summary name
	LocalSummary[1024],	// local summary path (Papertrail)
	JobFolder[1024],	// Summary and jobs
	LocalFolder[1024];	// LogFolder for 'papertrail' and local summaries

typedef struct {
	VTYPE* Content;	// pointer to VTYPE list
#ifndef _WIN64
	DWORD pad; // enforce same size in C++64/lite-C32
#endif
	char _Asset[16];
	char _Algo[16];
	int _TimeFrame;
	char Name[44];	// job name
} JOB;

JOB Jobs[MAXJOBS]; 
JOB* ThisJob = Jobs;
string JobNames[MAXJOBS] = { 0,0 }; // separate list needed for strselect
size_t VarSize; // Index into Contents 

string AlgoNames[MAXNAMES] = { 0,0 };
char* AlgoContents = 0; // variable blocks for the algos

typedef struct {
	int WFO,OOS;	// to override WFO cycles & OOS period
} CLUSTER;
CLUSTER CA[MAXCLUSTERS];

int WFOMin,WFOMax,WFOSteps = 0,
	OOSMin,OOSMax,OOSSteps = 0; // for heatmap
	
/////////////////////////////////////////////////////////////
void initJobs(int Mode)
{
	ThisJob = Jobs;
	*Summary = 0;
	*JobName = 0;
	if (Mode&8) {
		memset(Jobs,0,MAXJOBS*sizeof(JOB));
		memset(JobNames,0,MAXJOBS*sizeof(string));
		if (!JobContents)
			JobContents = (VTYPE*)malloc(MAXJOBS*MAXVSIZE);
		NumAlgos = 0;
	}
	if(!AlgoContents)
		AlgoContents = (char*)malloc(MAXALGOS*(MAXVSIZE+sizeof(JOB)));
	JobMode = Mode;
	NumJobs = NumClusters = 0;
}

void initAll()
{
	initJobs(0);
	strcpy(JobFolder,"Job");
	strcpy(LocalFolder,"Log");
	NumOptimized = DoTrain = 0;
	Values = (var*)&V;
	NumVars = sizeof(V)/sizeof(var);
	VarSize = NumVars*sizeof(VTYPE);
}

void alignVars()
{
	DoTrain = TRAINDEFAULT;
	for (i=0; i<NumVars; i++) {
		if(DO_CA && (i == N_WFO || i == N_OOS))
			continue; // don't overwrite CA variants
		Values[i] = Variables[i].Value;
		if (Variables[i].Step != 0.)
			DoTrain = 1; // allow training
	}
}

void saveVars()
{
	file_write(VARDATA,(char*)Variables,VarSize);
	alignVars();
}

void setVars(VTYPE* Content,int All)
{
	for (i=0; i<NumVars; i++)
		if ((Variables[i].Type&8) || All)
			memcpy(Variables+i,Content+i,sizeof(VTYPE));
	alignVars();
}

// save variable set for the threads
void saveThreads()
{
	if (Core > 1) return;
	var OriginalWFO = Variables[N_WFO].Value,
		OriginalOOS = Variables[N_OOS].Value;
	if (DO_CA) { // set current WFO cycles for the cores
		Variables[N_WFO].Value = Values[N_WFO];
		Variables[N_OOS].Value = Values[N_OOS];
	}
	file_write(VARCORE,(char*)Variables,VarSize);
	file_append(VARCORE,ThisJob,sizeof(JOB));
	Variables[N_WFO].Value = OriginalWFO;
	Variables[N_OOS].Value = OriginalOOS;
	if(!DO_CA) alignVars();
}

int loadAlgos()
{
#ifndef DO_VARIANTS
	return 0;
#endif
	size_t AlgoSize = VarSize+sizeof(JOB);
	size_t ReadSize = file_read(VARALGO,AlgoContents,MAXALGOS*AlgoSize);
	if (!ReadSize) return 0;
	if (ReadSize % AlgoSize) {
		print(_MSG,"\nError - %s outdated",VARALGO);
		return 0;
	} 
	// set up algos
	int NumRead = min(MAXALGOS,ReadSize/AlgoSize);
	setVars((VTYPE*)AlgoContents,0); // read vars from first algo
	char* Content = AlgoContents;
	for (i=0,j=0; i<NumRead; i++,Content+=AlgoSize) {
		memcpy(Jobs+j,Content+VarSize,sizeof(JOB));
#ifdef _EXCLUDE
		if(!Train && strstr(_EXCLUDE,Jobs[j].Name)) continue;
#endif
#ifdef _ALGOS // add only script-defined algos
		string AlgoName;
		while (AlgoName = of(_ALGOS))
			if(strstr(Jobs[j].Name,AlgoName))
#endif
		{
			Jobs[j].Content = (VTYPE*)Content;
			AlgoNames[j] = Jobs[j].Name;
			print(_MSG,"\nAlgo %s (%s, %iM)",
				AlgoNames[j],Jobs[j]._Asset,Jobs[j]._TimeFrame);
			j++;
		}
	}
	AlgoNames[j] = 0;
	Algos = AlgoNames;
	return NumAlgos = j;
}

void setLocalFolder(cstr Name)
{
	strcpy(LocalFolder,JobFolder);
	strcat(LocalFolder,strf("\\%sLog",RootName)); //Papertrail folder
	if(!file_date(LocalFolder)) 
		file_write(LocalFolder,0,0); // create Log subfolder
	strcat(LocalFolder,"\\");
	strcat(LocalFolder,Name);	// create papertrail folder in Log
	if(!file_date(LocalFolder))
		file_write(LocalFolder,0,0);
	if (!DO_CA && !DO_MRC)
		LogFolder = LocalFolder;	// store all logs locally
	else
		LogFolder = "Log";
}

string pureName(cstr Path)
{
	cstr Name = strrchr(Path,'\\');
	if (!Name) Name = Path;
	return strmid(Name,1,strcspn(Name+1,"."));
}

void setJobFolder(cstr JobPath)
{
	strcpy(JobFolder,JobPath);
	if (strrchr(JobPath,'.')) { // file name?
		cstr Name = strrchr(JobPath,'\\');
		strcpy(JobName,Name+1); // get pure name
		*(strrchr(JobName,'.')) = 0; // clip extension
		*(strrchr(JobFolder,'\\')) = 0; // clip name
	}
}

int runCA()
{
	string FileName = file_select("Job","WFO Profile\0*.csv\0\0");
	if(!FileName) return 0;
	string Cluster = file_content(FileName);
	if(!Cluster) return 0;
	if(strncmp(Cluster,"WFO",3)) return 0;
	string Pos = strchr(Cluster,'\n'); // skip header
	OOSSteps = WFOSteps = 1; 
	memset(CA,0,MAXCLUSTERS*sizeof(CLUSTER));
	for (N = 0; Pos && N<MAXCLUSTERS; N++) {
		//Jobs[N].Mode = ifelse(N == 0,2,3);
		CA[N].WFO = atof(Pos+1);
		if (!(Pos = strchr(Pos,','))) break;
		CA[N].OOS = atof(Pos+1);
		Pos = strchr(Pos,'\n');
		if (N == 0) {
			WFOMin = CA[N].WFO+VR(_WFO_Cycles); // min first, max last
			OOSMin = CA[N].OOS;
		} else { // detect by the steps if it's in matrix order
			if(CA[N].WFO > CA[N-1].WFO)
				WFOSteps++; 
			else if(CA[N].WFO < CA[N-1].WFO)
				WFOSteps = 1; 
			if(CA[N].OOS > CA[N-1].OOS)
				OOSSteps++; 
			else if(CA[N].OOS < CA[N-1].OOS)
				OOSSteps = 1; 
		}
	}
	if(!N) return 0;
	DoStart = 1;
	WFOMax = CA[N-1].WFO+VR(_WFO_Cycles);	// min first, max last
	OOSMax = CA[N-1].OOS;
	int IsMatrix = (OOSSteps > 1 && WFOSteps > 1 && N == OOSSteps*WFOSteps);  // regular matrix
	if (!IsMatrix) {
		Msg = strf("\nWFO %i Profiles",N);
	} else  // regular matrix
		Msg = strf("\nWFO %ix%i Matrix",OOSSteps,WFOSteps);
	if (!DO_JOBS) { // run CA with current variables
		initJobs(ifelse(IsMatrix,3,2));
		if (IsMatrix) dataNew(1,OOSSteps,WFOSteps);
		print(_MSG,Msg);
		print(TO_PANEL,Msg);
		return NumJobs = NumClusters = N;
	} else { // run CA with all loaded jobs
		if (DO_CA) // other CA loaded previously?
			NumJobs /= NumClusters;
		JobMode = 8+ifelse(IsMatrix,3,2);
		Msg = strf("%s, %i Jobs",Msg,NumJobs);
		print(_MSG,Msg);
		print(TO_PANEL,Msg);
		return NumJobs *= NumClusters = N;
	}
}

void runMRC()
{
	initJobs(4);
	NumJobs = VI(_MRC_Cycles);
	if (!*JobName) strcpy(JobName,"MRC");
	print(_MSG,"\n%s %i Cycles",JobName,NumJobs);
	print(TO_PANEL,"%s %i Cycles",JobName,NumJobs);
	DoStart = 1;
}

void saveVarsCSV()
{
	if (!NumVars) return;
	string FileName = file_select("Job","#csv");
	if(!FileName) return;
	file_write(FileName,RootName,0);
	//file_append(FileName,"\nName,Value,Min,Max,Step");
	for(j=0; j<NumVars; j++)
		file_append(FileName,strf("\n%s,%5.2f,%5.2f,%5.2f,%5.2f",
			Variables[j].Name,Values[j],Variables[j].Start,Variables[j].End,Variables[j].Step));
	print(_MSG,"\nJob saved to %s",FileName);
}

void printVarsToLog()
{
	for(j=0; j<NumVars; j++)
		print(TO_LOG,"\n%s = %5.2f",Variables[j].Name,Values[j]);
}

void printCore(cstr Text)
{
	file_append("Log\\CoreMsgs.txt",strf("\n%i: %s",Core,Text),0);
}

int loadVarsCSV(const char* FileName,int Quiet)
{
	if (!NumVars) return 0;
	string Content = file_content(FileName);
	if(!Content) {
		if(!Quiet) print(_MSG,"\nCan't open %s",FileName); 
		return 0; 
	}
	int Length = strcspn(Content," ,\n"); // compare begin of name
	if(strncmp(Content,RootName,Length-1))
		return 0; // saved from a different script
	int VarsRead = 0;
	for(i=0; i<NumVars; i++)
		if (Variables[i].Type&8) {
			string Field = strfield(Content,Variables[i].Name,1);
			if (!Field) continue;
			Values[i] = Variables[i].Value = atof(Field);
			Variables[i].Start = atof(strfield(Field,0,1));
			Variables[i].End = atof(strfield(Field,0,2));
			Variables[i].Step = atof(strfield(Field,0,3));
			VarsRead++;
		}
	if(!Quiet && !VarsRead) 
		print(_MSG,"\nInvalid format: %s",FileName);
	return VarsRead;
}

void updatePanel();

// copy variables and jobname from binary content
void readJob(int Job)
{
	if (Job >= NumJobs) return;
	ThisJob = Jobs +Job;
	if (*(ThisJob->Name)) {
		strcpy(JobName,ThisJob->Name);
		char LocalName[128];
		strcpy(LocalName,JobName);
		if (*(ThisJob->_Asset))
			strcat(LocalName,strf("_%s",strx(ThisJob->_Asset,"/","")));
		if (*(ThisJob->_Algo))
			strcat(LocalName,strf("_%s",ThisJob->_Algo));
		if (ThisJob->_TimeFrame > 0 && ThisJob->_TimeFrame >= VI(_Bar_Period))
			strcat(LocalName,strf("_%i",ThisJob->_TimeFrame));
		setLocalFolder(LocalName);
	}
	if (ThisJob->Content)
		setVars(ThisJob->Content,0);
}

void setupJob(int NCycle)
{
	int Cluster = 0,Job = NCycle;
	if (DO_CA) {
		Cluster = NCycle % NumClusters;
		Job = NCycle/NumClusters;
	}
	readJob(Job);
	if (DO_CA) {
		Values[N_WFO] = Variables[N_WFO].Value + CA[Cluster].WFO;
		Values[N_OOS] = CA[Cluster].OOS;
	}
}


void addJob(VTYPE* Content,string Name,string _Asset,string _Algo,int _TF)
{
	if(Content != Variables) memcpy(Content,Variables,VarSize);
	JOB *Job = Jobs+NumJobs;
	Job->Content = Content;
	if(_Asset) strcpy(Job->_Asset,_Asset);
	if(_Algo) strcpy(Job->_Algo,_Algo);
	Job->_TimeFrame = _TF;
	strcpy(Job->Name,Name);
	JobNames[NumJobs] = Job->Name;
	NumJobs++;
}

void addJobs(VTYPE* Content,string Name)
{
	string AssetName = 0,AlgoName = 0;
	int TF = 0;
#ifdef _ASSETS
	while(AssetName = of(_ASSETS))
#endif
#ifdef _ALGOS
	while(AlgoName = of(_ALGOS))
#endif
#ifdef _TIMEFRAMES
	while(TF = of(_TIMEFRAMES))
		if(TF >= VI(_Bar_Period))
#endif
	{
		//print(_MSG,"\n%s-%s-%i added",AssetName,AlgoName,TF);
		addJob(Content,Name,AssetName,AlgoName,TF);
	}
}

void setFirstVariant()
{
#ifdef _ASSETS
	strcpy(ThisJob->_Asset,of(_ASSETS));
	of((intptr_t)0);
#endif
#ifdef _ALGOS
	strcpy(ThisJob->_Algo,of(_ALGOS));
	of((intptr_t)0);
#endif
#ifdef _TIMEFRAMES
	ThisJob->_TimeFrame = of(_TIMEFRAMES);
	of((intptr_t)0);
#endif
	return;
}

// load single job with no asset/algo/TF expansion
void loadJob()
{
	string FileName = file_select("Job","csv");
	if(!FileName) return;
	if (!loadVarsCSV(FileName,0)) return;
	initJobs(8);
// set up summary and target folders
	setJobFolder(FileName);
	setFirstVariant();
	addJob(JobContents,JobName,ThisJob->_Asset,ThisJob->_Algo,ThisJob->_TimeFrame);
	saveVars();
	updatePanel();
	print(TO_PANEL,JobName);
}

void loadJobsFromFolder()
{
	string DirName = file_select("Job","CSV Folder\0*.csv\0\0");
	if(!DirName) return; // aborted
	string End = strrchr(DirName,'\\');
	if (!End) return;
	*End = 0; // separate the folder from the file
	initJobs(8);
	print(_MSG,"\nLoad jobs from %s",DirName);
	setJobFolder(DirName);
	char FileName[1024];
	strcpy(FileName,DirName);
	strcat(FileName,"\\*.csv");
	string JobFile;
	VTYPE* Content = JobContents;
	for (JobFile = file_next(FileName); JobFile; JobFile = file_next(0)) 
	{
		if (strstr(JobFile,"ummary")) continue;
		if (!loadVarsCSV(strx(FileName,"*.csv",JobFile),1)) continue;
		addJobs(Content,strx(JobFile,".csv",""));
		if (NumJobs >= MAXJOBS) break;
		Content += NumVars;
	}
	print(_MSG,"\n%i jobs loaded",NumJobs);
	print(TO_PANEL,"Run %i jobs from %s",NumJobs,strrchr(DirName,'\\')+1);
}

// load only jobs with net profit > 0 and R2 > 0
void loadJobsFromSummary()
{
	string FileName = file_select("Job","Summaries\0*ummary.csv\0\0");
	if(!FileName) return; // aborted
	string List = (string)zalloc(128*4000);
	if(!file_read(FileName,List,0)) return;
	initJobs(8);
	strcpy(Summary,FileName);
	setJobFolder(FileName);
	print(_MSG,"\nLoad jobs from %s",JobName);
	VTYPE* Content = JobContents;
	string End = List + strlen(List);
	int NumParsed = 0;
	while((List = strchr(List,'\n')) && ++List < End && NumJobs < MAXJOBS) {
		NumParsed++;
		var Profit = strvarCSV(List,0,N_PRF,0);
		var R2 = strvarCSV(List,0,N_R2,0);
// load only profitable jobs
		if (*List == '#' || Profit < PRF_LIMIT || R2 < R2_LIMIT) continue;
		strcpy(JobName,strmid(List,0,strcspn(List," ,")));
		FileName = strf("%s\\%s.csv",JobFolder,JobName);
		if (!loadVarsCSV(FileName,0)) continue;
		string _Asset = strtextCSV(List,0,N_ASSET,0);
		string _Algo = strtextCSV(List,0,N_ALGO,0);
		int _TF = strvarCSV(List,0,N_TF,0);
		addJob(Content,JobName,_Asset,_Algo,_TF);
		print(_MSG,"\n%s (%s,%s,%i min)",JobName,_Asset,_Algo,_TF);
		Content += NumVars;
	}
	print(_MSG,"\n%i jobs from %i loaded",NumJobs,NumParsed);
	print(TO_PANEL,"%i jobs from %s",NumJobs,strrchr(Summary,'\\')+1);
}

void createAlgosFromSummary()
{
	string FileName = file_select("Job","Summaries\0*ummary.csv\0\0");
	if(!FileName) return; // aborted
	initJobs(0);
	setJobFolder(FileName);
	string List = (string)zalloc(128*4000);
	strcpy(List,file_content(FileName));
	print(_MSG,"\nCreate algos from %s",JobName);
	VTYPE* Content = (VTYPE*)AlgoContents;
	string End = List + strlen(List);
	int NLine = 0;
	while((List = strchr(List,'\n')) && ++List < End && NumJobs < MAXALGOS) {
		NLine++; // line number in summary
		var CA_Percent = strvarCSV(List,0,N_CA,0);
// load only algos that passed the CA
		if (*List == '#' || CA_Percent < CA_LIMIT) continue;
		strcpy(JobName,strmid(List,0,strcspn(List," ,")));
		FileName = strf("%s\\%s.csv",JobFolder,JobName);
		if (!loadVarsCSV(FileName,1)) continue;
		string _Asset = strtextCSV(List,0,N_ASSET,0);
		string _Algo = strtextCSV(List,0,N_ALGO,0);
		int _TF = strvarCSV(List,0,N_TF,0);
		if(*_Algo > ' ')	// use original algo name 
			strcpy(JobName,strf("%s_%i",_Algo,NLine));
		else
			strcpy(JobName,strf("%s_%i",JobName,NLine));
		print(_MSG,"\nAdding %s (%s, %iM, CA %.0f)",JobName,_Asset,_TF,CA_Percent);
		addJob(Content,JobName,_Asset,_Algo,_TF);
		AlgoNames[NumJobs-1] = Jobs[NumJobs-1].Name;
		Content += NumVars;
	}
	NumAlgos = NumJobs;
	AlgoNames[NumAlgos] = 0;
	Algos = AlgoNames;
	JobMode = NumJobs = 0;
	file_copy(strx(VARALGO,"bin","bak"),VARALGO);
	file_delete(VARALGO);
	for (i=0; i<NumAlgos; i++) {
		file_append(VARALGO,Jobs[i].Content,VarSize);
		file_append(VARALGO,Jobs+i,sizeof(JOB));
	}
	print(_MSG,"\n%i algos with CA > %.0f%%",NumAlgos,(var)CA_LIMIT);
	print(TO_PANEL,"%i algos",NumAlgos);
}

void sortSummary()
{
	if (!VI(_Criteria)) return;
	string Summary = file_select("Summary","Summaries\0*ummary.csv\0\0");
	if(!Summary) return; // aborted
	file_sortCSV(Summary,VI(_Criteria),1);
}

string sfitoa(var Num)
{
	if(Num == round(Num)) 
		return sftoa(Num,0);
	return sftoa(Num,-2);
}

#define VNAME	0
#define VMODE	3
#define VVAL	4
#define VMIN	5
#define VMAX	6
#define VSTEP	7
#define VDESC	8
#define VLOAD	"O"
#define VFIX	"X"

void setupRange(int N,DWORD Color)
{
	VTYPE *Var = Variables + N;
	int Row = N+1, Type = 2, Grey = 1;
	if (N <= NV) { Type = 1; Grey = -1; Color = SYSCOLOR; }
	if (Var->Start == Var->End) {
		panelSet(Row,VMIN,"",Color,1+4,Type);
		panelSet(Row,VMAX,"",Color,1+4,Type);
	} else {
		panelSet(Row,VMIN,sfitoa(Var->Start),Color,1+4,Type);
		panelSet(Row,VMAX,sfitoa(Var->End),Color,1+4,Type);
	}
	if (Var->Step != 0.)
		panelSet(Row,VSTEP,sfitoa(Var->Step),WHITE,1+4,Type);
	else if (Var->Type&1)
		panelSet(Row,VSTEP,"0",Color,1+12,Type);
	else
		panelSet(Row,VSTEP,"",Color,1,Type);
	if(Var->Type&8)
		panelSet(Row,VMODE,VLOAD,Color,12+2+Grey,4);
	else
		panelSet(Row,VMODE,VFIX,Color,12+2-Grey,4);
}

void updateVar(int N)
{
	VTYPE *Var = Variables + N;
	panelSet(N+1,VVAL,sfitoa(Values[N]),0,0,0);
	if(Var->Start < Var->End
		&& !between(Values[N],Var->Start,Var->End))
		panelSet(N+1,VVAL,0,RED,1+4,2); 
	else
		panelSet(N+1,VVAL,0,0,1+4,2);
	if(N == N_INVEST)
		ResetSlider = 1;
}

// display variables in the panel
void updatePanel()
{
	if (Core > 1) return;
	for (i=0; i<NumVars; i++) {
		updateVar(i);
		if(i>NV) // no new range for grey variables
			setupRange(i,0); 
	}
}

void doMenu();

// Load Variable definitions from CSV, set up panel
int initVars(int DoPanel,int DoDefault)
{
	if (DoDefault) {
		initAll();
		print(_MSG,"\nReset");
	}
	int Style = 12+16;
	DWORD Color = WHITE;
	if(DoPanel) { // only at start
		panel(NumVars+1,20,Color,FIELDWIDTH);
		print(TO_PANEL,"%s Evaluation Shell V%s",RootName,EFVERSION);
		panelMerge(0,VDESC,1,3);
		panelSet(0,VNAME,"Name",Color,Style,1);
		panelSet(0,VMODE,"Fixed",Color,Style,1);
		panelSet(0,VVAL,"Value",Color,Style,1);
		panelSet(0,VMIN,"Min",Color,Style,1);
		panelSet(0,VMAX,"Max",Color,Style,1);
		panelSet(0,VSTEP,"Step",Color,Style,1);
		panelSet(0,VDESC,"Description",Color,Style,1);
		doMenu();
	}
	if (!DoDefault) { // load vars from binary files
		memset(Variables,0,NumVars*sizeof(VTYPE));
		if(VarSize == file_read(VARDATA,(char*)Variables,0))
			alignVars();
		else DoDefault = 1; // # of vars changed
		if(!DoDefault) if(loadAlgos()) 
			print(TO_PANEL,"%i Algos",NumAlgos);
#ifdef _DEPLOY
		return 1;
#endif
	}
	string Pos = (string)zalloc(80000);
	file_read(SYSLIST,Pos,0);
	if(!(Pos = strstr(Pos,"struct"))) return 0;
	for(N=0; N<NumVars; N++) {
		if(N == NV+1) // read further vars from strategy source
			file_read(VARLIST,Pos,0);
		if(!(Pos = strstr(Pos,"\nvar "))) break;
		string Name = Pos+5;
		string Next = strchr(Name,'\n');
		if (!Next) break; // Next = End;
		*Next = 0; // clip line at end
		if(!(Pos = strchr(Name,';'))) break;
		*(Pos++) = 0; // clip name at end
// parse description, value, start, end, step
		string Desc = strchr(Pos,';');
		Pos = strstr(Pos,"//");
		if (Desc)
			*(Desc++) = 0; // clip range at end
		else
			Desc = Pos+2;
		string Range = 0,Step = 0,
			Val = strchr(Pos,'=');
		if(Val)
			Range = strchr(Val,',');
		if(Range) 
			Step = strchr(Range+1,',');

		VTYPE* Var = Variables+N;
		strcpy(Var->Name,Name);
		if(DoDefault) {
			if(Val) Var->Value = atof(Val+1);
#ifdef _BAR_PERIOD
			if(N==0) Var->Value = _BAR_PERIOD;
#endif
#ifdef _LOOKBACK_BARS
			if(N==1) Var->Value = _LOOKBACK_BARS;
#endif
#ifdef _WFO_CYCLES
			if(N==N_WFO) Var->Value = _WFO_CYCLES;
#endif
#ifdef _BACKTEST_START
			if(N==N_START) Var->Value = _BACKTEST_START;
#endif
#ifdef _BACKTEST_END
			if(N==N_END) Var->Value = _BACKTEST_END;
#endif
#ifdef _NO_CORES
			if(N==N_CORES) Var->Value = 0;
#endif
			Values[N] = Var->Value;
			Var->Type = 0;
			Var->Step = Var->Start = Var->End = 0;
			if (N > NV) 
				Var->Type |= 8; // all script vars are by job
		}
#ifdef _ALGOS
		if(*Name != '_' && strchr(Name,'_')) {
			string AlgoName;
			/*if(!strncmp(Name,"ALL_",4))
					Var->Type |= 4;
			else*/
			i = 0;
			while (AlgoName = of(_ALGOS)) {
				if (!strncmp(AlgoName,Name,strcspn(Name,"_"))) {
					Var->Type |= 2; // algo specific
					Color = ALGOCOLORS[i%5]; // use slightly different colors per algo
				}
				i++;
			}
		}
#endif
		if (DoPanel) {
			Style = 1;
			if (N <= NV) Color = SYSCOLOR;
			else if (!(Var->Type&2)) Color = GLOBALCOLOR;
			if (!Desc) Desc = (string)"";
			panelMerge(N+1,VNAME,1,3);
			panelMerge(N+1,VDESC,1,12);
			panelSet(N+1,VNAME,Name,Color,Style,1);
			panelSet(N+1,VDESC,Desc,Color,Style,1);
			if (N == N_START || N == N_END) {
				panelMerge(N+1,VVAL,1,2);
				panelSet(N+1,VVAL,sfitoa(Var->Value),VARCOLOR,1+12,2);
			} else
				panelSet(N+1,VVAL,sfitoa(Var->Value),VARCOLOR,1+4,2);
		}
		if (Range) {
			if(DoDefault) Var->Start = atof(Range+1);
			Range = strstr(Range,"..");
			if (!Range) break; // wrong syntax
			if (DoDefault) Var->End = atof(Range+2);
			if (Step) {
				Var->Type |= 1; // optimize
				if (DoDefault) Var->Step = atof(Step+1);
			}
		}
		if(DoPanel) setupRange(N,VARCOLOR);
		*(Pos = Next) = '\n'; // restore previous line end
	}
	if (DoDefault) saveVars();
	return 1;
}

void viewJob()
{
	if (!*JobNames || !NumJobs) return;
	int Job = strselect((const char**)JobNames,NumJobs);
	if (Job >= 0) {
		print(_MSG,"\n%s loaded to panel",JobNames[Job]);
		readJob(Job);
		updatePanel();
	}
}

void openDownload()
{
	exec("https://zorro-project.com/download.php#history","",0); 
}

void doMenu()
{
	panelSet(-1,0,"Start",0,0,0);
	int N=0;
	panelSet(-2,N++,"Reset",0,0,0);
#ifndef NO_VARS
	panelSet(-2,N++,"Save Job to CSV",0,0,0);
	panelSet(-2,N++,"Load Single Job",0,0,0);
	panelSet(-2,N++,"Load Multiple Jobs",0,0,0);
	panelSet(-2,N++,"Load Jobs from Summary",0,0,0);
	panelSet(-2,N++,"Browse Jobs",0,0,0);
#endif
	if(Train) panelSet(-2,N++,"Run Cluster Analysis",0,0,0);
	panelSet(-2,N++,"Run Montecarlo Analysis",0,0,0);
#ifndef NO_VARS
	panelSet(-2,N++,"Rearrange Summary",0,0,0);
#endif
#ifdef DO_VARIANTS
	panelSet(-2,N++,"Create Algos from Summary",0,0,0);
#endif
	panelSet(-2,N++,"Download History",0,0,0);
}

DLLFUNC void click(int Row, int Col) 
{
	if(!is(RUNNING)) return;
	if(Row == -2) { // action box
		int N=0;
		if(N++ == Col) {
			initVars(0,1);
			updatePanel();
			print(TO_PANEL,"Reset to defaults");
		}
#ifndef NO_VARS
		if(N++ == Col) saveVarsCSV();
		if(N++ == Col) loadJob(); 
		if(N++ == Col) loadJobsFromFolder();
		if(N++ == Col) loadJobsFromSummary();
		if(N++ == Col) viewJob();
#endif
		if(Train) if(N++ == Col) runCA(); 
		if(N++ == Col) runMRC(); 

#ifndef NO_VARS
		if(N++ == Col) sortSummary(); 
		if(N++ == Col) createAlgosFromSummary();
#endif
		if(N++ == Col) openDownload(); 
		sound("click.wav");
		return;
	}
	if(Row == -1) { // start button
		DoStart = 1; 
		sound("click.wav");
		return;
	}
	if(Row < 0) return;
	string Text = panelGet(Row,Col);
	int i = Row-1;
	if(Col == VVAL) {
		panelSet(Row,Col,0,WHITE,0,0);
		Values[i] = Variables[i].Value = atof(Text);
		updateVar(i);
	} else if(Col == VMIN) {
		panelSet(Row,Col,0,WHITE,0,0);
		Variables[i].Start = atof(Text);
		setupRange(i,0);
	} else if(Col == VMAX) {
		panelSet(Row,Col,0,WHITE,0,0);
		Variables[i].End = atof(Text);
		setupRange(i,0);
	} else if(Col == VSTEP) {
		panelSet(Row,Col,0,WHITE,0,0);
		Variables[i].Step = atof(Text);
		setupRange(i,WHITE);
	} else if(Col == VMODE) {
		Variables[i].Type ^= 8; // toggle job/override
		setupRange(i,0);
	} else return;
	sound("click.wav");
	saveVars();
}

var PRR()
{
	var wFac = 1./sqrt(1.+NumWinTotal); 
	var lFac = 1./sqrt(1.+NumLossTotal);
	var Win = WinTotal, Loss = LossTotal;
// remove best and worst trades
	if(NumLossTotal > 1) {
		Loss -= LossMaxTotal*(NumLossTotal-1)/NumLossTotal;
		Win -= WinMaxTotal*(NumWinTotal-1)/NumWinTotal;
	}
// return PRR
	return (1.-wFac)/(1.+lFac)*(1.+Win)/(1.+Loss);
}

var _objective()
{
	if(!NumWinTotal) return 0; // nothing to calculate
	switch(VI(_Objective)) {
	case 1:
		return PRR();
	case 2:
		return ReturnR2*PRR();
	case 3:
		return (WinTotal-LossTotal)/fix0(DrawDownMax);
	case 4:
		return (WinTotal-LossTotal)/fix0(MarginMax);
	case 5: // gross profit per day
		return (WinTotal-LossTotal)*24*60/NumMinutes;
	case 6: // profit per trade
		return (WinTotal-LossTotal)/(NumWinTotal+NumLossTotal);
	}
	return 0;
}

void setObjective()
{
	if(VI(_Objective)) 
		event(1,(void*)_objective);
}

/////////////////////////////////////////////////////////////

// at any bar, before asset selected
void initBar()
{
	//ignore(47);
	//if (!Live) SaveMode = 0;
	Verbose = VI(_Verbose);
#ifdef VERBOSE
	Verbose = VERBOSE;
#endif
#ifndef _DEPLOY
	if (Verbose > 0 && !(JobMode&7) && Core <= 1) {
		set(LOGFILE,PLOTNOW);
		LogNumber = -1; // allow logs in main cycles
		if(Init && Test) printVarsToLog();
	} else { // no logs for CA/MRC
		set(LOGFILE|OFF,PLOTNOW|OFF);
		LogNumber = 0;
		MonteCarlo = 0;
	}
	if (DO_JOBS)
		setf(PlotMode,PL_FILE);
	else
		resf(PlotMode,PL_FILE);
#endif

	BarPeriod = VR(_Bar_Period);
	//BarOffset = VR(_Bar_Offset;
	//BarOffset = (BarOffset/100)*60 + BarOffset%100; // convert HHMM
	LookBack = VI(_LookBack_Bars);
	StartDate = VI(_Backtest_Start);
	EndDate = VI(_Backtest_End);
	//StartWeek = STARTWEEK;
	if(Test) NumSampleCycles = VI(_Oversampling);
	//Fill = 5;	// next tick pessimistic
	//Interest = 3;
	//History = "*.t6";
#ifdef ZONE
	BarZone = LogZone = ZONE;
#endif
	if (VI(_Backtest_Mode) >= 2)
		set(TICKS);
	if (VI(_Backtest_Mode) >= 3)
		History = "*.t1";

// initialize train mode
#ifndef NO_VARS
	if(!DoTrain) {
		set(PARAMETERS|OFF,FACTORS|OFF);
	}
#endif
	set(TESTNOW);
	//if(!is(RULES)) set(PARAMETERS);
	NumCores = VI(_Max_Threads); 
	g->numWFOCycles = round(VR(_WFO_Cycles));
	g->nDataSplit = 100-VR(_WFO_OOS);
//	if(VR(_Max_Trades) > 0) TrainMode |= LIMITS; // observe maxlong/short

//alternative: WFO cycles by period
	//int WFO_Bars = VR(_WFO_Period * Bars_per_day; // need bars per day
	//int TestWindow = round(WFO_Bars*0.01*_WFO_OOS);
	//int TrainWindow = WFO_Bars-TestWindow;
	//NumWFOCycles = (Bars_total-TrainWindow)/TestWindow + 1;
//alternative: cycles per year
	//int Years = VR(_Backtest_End - VR(_Backtest_Start;
	//if(Years > 10000) Years /= 10000; // exact dates given
	//NumWFOCycles = round(VR(_WFO_Cycles *Years);

	switch (VI(_Investment)) {
	case 1:
		set(ACCUMULATE|OFF);
		Margin = 0.000001;
		Capital = 0;
		Lots = slider(1,1,0,20,"Lots","Lot amount per trade");
		if (ResetSlider) slider(1,1);
		break;
	case 2:
		set(ACCUMULATE|OFF);
		Capital = 0;
		Lots = 1;
		Margin = slider(1,200,0,2000,"Margin","Margin per trade");
		if (ResetSlider) slider(1,200);
		break;
	case 3:
		set(ACCUMULATE,FACTORS);
		Lots = 1;
		Margin = OptimalF*slider(1,200,0,2000,"OptimalF","Amount*OptimalF");
		if (ResetSlider) slider(1,200);
		break;
	case 4:
		set(ACCUMULATE,FACTORS);
		Capital = 10000;
		Lots = 1;
		Margin = OptimalF*Balance*0.01*slider(1,5,0,50,"Account%","Account percent reinvestment");
		if (ResetSlider) slider(1,5);
		break;
	case 5:
		set(ACCUMULATE,FACTORS);
		Capital = 10000;
		Lots = 1;
		Margin = OptimalF*Capital*sqrt(1+ProfitClosed/abs(Capital))
			*0.01*slider(1,5,0,50,"Sqrt","Square root reinvestment");
		if (ResetSlider) slider(1,5);
		break;
	}
	ResetSlider = 0;
}

var optv(var* Parameter)
{
	int N = ((intptr_t)Parameter-(intptr_t)Values)/sizeof(var);
	if(N >= NumVars) return 0;
	VTYPE* Var = Variables + N;
	if(Var->Step == 0.) 
		return Values[N] = Var->Value;
	var Offs = ifelse(Var->Start<0,-Var->Start,0);
	Values[N] = optimize(Var->Name,
		Var->Value+Offs,Var->Start+Offs,Var->End+Offs,
		Var->Step,0);
	if(!(Var->Type&8)) // fixed 
		return Values[N] = Var->Value;
	return Values[N] -= Offs;
}

// called from run()
// select asset, algo, timeframe
void assetLoop()
{
	if(!NumAlgos) 
		set(FACTORS|OFF);	// no factors for variant testing unless algos are used
	if (!NumJobs && !NumAlgos) // run with the first elements
		setFirstVariant();
	if (*(ThisJob->_Asset))
		asset(ThisJob->_Asset);
	if (!NumAlgos && *(ThisJob->_Algo)) // _Algo = algo name root 
		algo(ThisJob->_Algo);
	if (ThisJob->_TimeFrame > 0) {
		TimeFrame = max(1,ThisJob->_TimeFrame/BarPeriod);
		if (Init && ThisJob->_TimeFrame < BarPeriod)
			print(_MSG,"\nError: time frame %i < bar period %.0f",ThisJob->_TimeFrame,BarPeriod);
	}

	if(VI(_Phantom)) {
		if(phantom(0,VI(_Phantom),VI(_Phantom)*5))
			TradeMode |= TR_PHANTOM;
		else
			TradeMode &= ~TR_PHANTOM;
	}
	if (VI(_Backtest_Mode) < 0)
		Spread = Commission = RollLong = RollShort = 0;

#ifdef AUTO_OPTIMIZE
	if (!DoTrain) return;
	int len = (int)strlen(Algo);
	for(i=NV+1; i<NumVars; i++) {
		VTYPE *Var = Variables+i;
		if(Var->Step != 0. && (Var->Type&1) && (len <= 1 
			|| !(Var->Type&2) // optimize for all algos
			|| !strncmp(AlgoName,Var->Name,strcspn(Var->Name,"_"))))
			//			|| (!(Var->Type&6) && Num == 0)))
		{
			var Offs = ifelse(Var->Start<0,-Var->Start,0);
			Values[i] = optimize(Var->Name,
				Var->Value+Offs,Var->Start+Offs,Var->End+Offs,
				Var->Step,0);
			Values[i] -= Offs;
			double p;
			if((Var->End-Var->Start > 10) || (Var->Step > 0 && modf(Var->Step,&p) < 0.001))
				Values[i] = round(Values[i]);
			if (!Train && Init) {
				Var->Value = Values[i];
				updateVar(i);
				print(_MSG,"\nOptimized %s (%.2f)",Var->Name,Values[i]);
			}
		}
	}
#endif

}

// at the begin of any TotalCycle
void initJobCycle(int NCycle)
{
	setObjective();
	if(VI(_Train_Mode) == 2) {
		setf(TrainMode,GENETIC);
		resf(TrainMode,ASCENT|BRUTE);
	}
	else if(VI(_Train_Mode) == 3) {
		setf(TrainMode,BRUTE);
		resf(TrainMode,ASCENT|GENETIC);
	} else {
		setf(TrainMode,ASCENT);
		resf(TrainMode,GENETIC|BRUTE);
	}
#ifdef TRAINCYCLES
	if (VR(_Train_Mode) == 1. && NumOptimized > 4) // Ascent
		NumTrainCycles = TRAINCYCLES+NumOptimized/4;
	else
		NumTrainCycles = TRAINCYCLES;
#endif
	//if(!Live) set(PRELOAD);	// enforce same start condition for all assets

	switch(JobMode) { // on all cores
	case 4: 
		resf(Detrend,SHUFFLE); 
		set(PRELOAD);	// reload the history
		if(NCycle) JobMode = 5;
		break;
	case 5:
		setf(Detrend,SHUFFLE); // also for cores
		set(PRELOAD);
		break;
	default:
		resf(Detrend,SHUFFLE); 
		break;
	}
	
	if (Core <= 1) {
//Set up the number of main cycles
		NumTotalCycles = NumJobs;
		Command[0] = JobMode; // for the cores
		if(DO_JOBS || DO_CA || DO_MRC) 
			setupJob(NCycle);
		if(NCycle) updatePanel();
		saveThreads(); //vars & job for the threads

		switch(JobMode) {
		case 8: // Var job
			print(_MSG,"\nRun Job %i %s",NCycle+1,JobName);
			print(TO_INFO,"Job %i %s",NCycle+1,JobName);
			break;
		case 2: // WFO profile
		case 3: // WFO matrix
			print(TO_INFO,"WFO %ix%i%%",VI(_WFO_Cycles),VI(_WFO_OOS));
			break;
		case 8+2:
		case 8+3:
			print(TO_INFO,"WFO %s-%i %ix%i%%",JobName,(NCycle+1)/max(1,NumClusters),VI(_WFO_Cycles),VI(_WFO_OOS));
			break;
		case 4: // Reality Check, original prices
			print(TO_INFO,"Original Run");
			break;
		case 5: // Reality Check, shuffled prices
			print(TO_INFO,"Random Run %i",NCycle);
			break;
		}
	}
}


// Main function ////////////////////////////////////////////////
DLLFUNC int run()
{
#ifndef _DEPLOY
	if (!require(-3.01)) _exit;
#endif
#ifdef LOGNUMBER
	LogNumber = LOGNUMBER;
#endif
#ifdef ENFORCE
	if(!*Define) Define = ENFORCE;
#endif // ENFORCE

	if(is(FIRSTINITRUN)) 
	{ 
		initAll();
		if(Core > 1) {
			char* Content = file_content(VARCORE);
			if(Content) { // needed for CA
				setVars((VTYPE*)Content,1); // get the variables
				memcpy(ThisJob,Content+VarSize,sizeof(JOB)); // get asset,algo,tf
			} else { 
				print(_MSG,"\nError - %s",VARCORE); 
				printCore("No Vars"); 
				_exit;
			}
			if (Command[1]) { // train algos
				if (!loadAlgos()) {
					print(_MSG,"\nError - %s",VARALGO);
					printCore("No Algos");
					_exit;
				}
			}
			JobMode = Command[0];
			NumJobs = 1;
		} else if(*Define) { // batch mode
			initVars(0,0); // read vars
			print(_MSG," %s",Define);
			if(strstr(Define,".csv")) {
				if(!loadVarsCSV(Define,0)) 
					return quit("!Can't read CSV"); 
			}
		} else { //  started from script
#ifdef _STARTMSG
			printf(" -> %s",_STARTMSG);
#endif
#ifdef _DEPLOY
			if(!initVars(0,0)) // no panel, no default
				_exit; 
#else
			set(LOGFILE);	// log the start messages
			if(!initVars(1,0)) // let panel appear
				_exit; 
			if(is(FIRSTINITRUN)) 
				DoStart = 0;
			while (wait(100) && !DoStart);
			if(!DoStart) 
				_exit;
			else
				panelSet(-1,0,"Result",0,0,0);
#endif
		} 
	}

// Cycle setup at begin of any cycle
	static int NCycle = -1,DoPrint = 0;
	if(TotalCycle-1 > NCycle || (Test && Init)) {
		NCycle = TotalCycle-1;
		initJobCycle(NCycle);
		DoPrint = 1; // print initial messages
	}

// General setup at any bar
	initBar();
#ifdef _ASSETLIST
	assetList(_ASSETLIST);
#endif
#ifdef DO_SYMBOLS
	if (Live && Init)
		while (assetAdd(of(Assets)))
			updateSymbol();
#endif
#ifdef CORETEST
	if(is(FIRSTINITRUN)) { // thread
		if(Core > 1) LogNumber = Core;
		else LogNumber = TotalCycle;
		printCore(strf("%s Cyc %i/%i WFO %i/%i Cmd %i %i %i WFO %.0fx%.0f%%",
			Script,TotalCycle,NumTotalCycles,
			WFOCycle,g->numWFOCycles,
			Command[0],Command[1],Command[2],
			VR(_WFO_Cycles),VR(_WFO_OOS)));
	}
#endif
	if(Core <= 1 && Train && DoPrint) {
		print(_MSG|TRAINMODE,"\nTrain %s %s %.0f ------------------",
			Asset,Algo,TimeFrame*BarPeriod);
		DoPrint = 0;
	}
	if(NumAlgos) {
		Command[1] = NumAlgos; // tell the cores to load algos
		while(algo(loop(Algos))) {
			ThisJob = Jobs + Itor1;
			if(!Train || Init)	// only one algo is trained at a time
				setVars(ThisJob->Content,0);
			strategy();
		}
	} else strategy();

	if(is(STEPWISE)) 
		updatePanel(); // display vars in debugging mode
	return 0;
}

DLLFUNC void evaluate()
{
	if(!Test || Core > 1) return; // use threads for training only
	var NumTrades = NumWinTotal+NumLossTotal;
	if (NumTrades == 0. || !NumMinutes) {
		print(_MSG,"\n%s - no trades in test run",JobName);
		return; // ignore this cycle
	}
	int NCycle = max(0,TotalCycle-1);
	var NetProfit = WinTotal-LossTotal-InterestCost;
	var WinRate = 100.*NumWinTotal/NumTrades;
	var Years = NumMinutes/(365.25*24*60);
	var PFactor = clamp(WinTotal/fix0(LossTotal),-9.9,9.9);
	var Calmar = 100.*NetProfit/fix0(DrawDownMax)/Years;
	var Return = 100.*NetProfit/fix0(DrawDownMax+MarginMax)/Years;
	var CAGR = 100.*(pow((NetProfit+MarginMax)/MarginMax,1./Years)-1.);
	var Sharpe = ReturnMean/fix0(ReturnStdDev)*sqrt(InMarketBars/Years);
	var Obj = _objective();
	static var CA_Percent = 0;
	if (DO_CA) {
		if (NCycle % NumClusters == 0)
			CA_Percent = 0; // reset percentage for cluster analysis
		if (PFactor > 1.)
			CA_Percent += 100./NumClusters;
	}
	static var OriginalResult = 0,PV = 0,StepWidth = 1;
	var EndResult = Return;
	switch (VI(_Criteria)) {
		case 7: EndResult = NetProfit; break;
		case 13: EndResult = WinRate; break; 
		case 14: EndResult = Obj; break;
		case 15: EndResult = PFactor; break;
		case 16: EndResult = (WinTotal-LossTotal)/NumTrades; break;
		case 17: EndResult = Return; break;
		case 18: EndResult = CAGR; break;
		case 19: EndResult = Calmar; break;
		case 20: EndResult = Sharpe; break;
		case 21: EndResult = ReturnR2; break;
	}

	*LocalSummary = 0;
	string Name = JobName;
	switch(JobMode) {
	case 0: 
		if (!*JobName) break; // no job loaded -> no summary
	case 10: // multiple CA profiles
	case 11: // multiple CA matrix
	case 8: { // single or multiple jobs, or multiple CA
		if(!*Summary) // if not already set by selecting Jobs from a summary
			strcpy(Summary,strf("%s\\%s_Summary.csv",JobFolder,RootName));
		strcpy(LocalSummary,strf("%s\\%s_History.csv",LocalFolder,JobName));
		break;
	}
	case 2: // single CA profile
		Name = strf("Profile_%i",TotalCycle-1);
		strcpy(LocalSummary,strf("%s\\%s_CA.csv",LogFolder,RootName));
		plotBar("Result/Run",(int)TotalCycle,TotalCycle,EndResult,BARS,BLACK);
		break;
	case 3: { // single CA matrix
		strcpy(LocalSummary,strf("%s\\%s_CA.csv",LogFolder,RootName));
		Name = strf("Matrix_%i",TotalCycle-1);
		int CyclesIdx = (TotalCycle-1)/OOSSteps,OOSIdx = (TotalCycle-1)%OOSSteps;
		dataSet(1,OOSIdx,CyclesIdx,EndResult);
		break;
	}
	case 4: // first MC cycle
		strcpy(LocalSummary,strf("%s\\%s_MRC.csv",LogFolder,RootName));
		Name = (string)"Original";
		OriginalResult = EndResult; 
		StepWidth = OriginalResult/min(50,10+NumTotalCycles);
		PV = 0;
		JobMode = 5; // Now produce random results
		break;
	case 5: // shuffled MC cycles
		strcpy(LocalSummary,strf("%s\\%s_MRC.csv",LogFolder,RootName));
		Name = strf("Random_%i",TotalCycle-1);
		if(EndResult >= OriginalResult)
			PV += 100./NumTotalCycles;
		if(EndResult < 2.*OriginalResult)	{ // restrict image to twice the original
			if(abs(EndResult) < StepWidth/2)
				EndResult = sign(EndResult) * StepWidth/2; // avoid wrong labels
			if(EndResult >= OriginalResult)
				plotHistogram("Random+",EndResult,StepWidth,1,RED);
			else
				plotHistogram("Random-",EndResult,StepWidth,1,RED); // DARKGREEN);
		}
		break;
	}

// Append to the summary
//_LOG(strf("\n%i: %s %s\n",TotalCycle,Summary,LocalSummary));
	if(*Name && (*Summary || *LocalSummary)) 
	{
		if(TotalCycle <= 1) {
			cstr Line = "Job,Asset,Algo,TF,Days,WFO,OOS%,Profit,Margin,MaxDD,PeakDD%,TimeDD%,Trades,Win%,Obj,P/L,P/Trade,Return,CAGR%,Calmar%,Sharpe,R2,CA%\n";
			if(*Summary && !file_date(Summary)) 
				file_write(Summary,Line,0);
			if(*LocalSummary && !file_date(LocalSummary)) 
				file_write(LocalSummary,Line,0);
		}	//0Job,1Ass,2Alg,3Bar,4Days,5WFOCy,6OOS%,7NetPr,8Invest,9MaxDD,10DD%,11DDTim,12NTrad,13WinRa,14Obj,15PF,16P/Tr,17Rtrn,18CAGR,19Calm,20Sharp,21R2,22CA 
		string Line = 
		strf("%-10s,%-7s,%-4s,%4.0f,%6i,%3.0f,%3.0f,%6.0f,%6.0f,%6.0f,%4.0f,%3.0f,%5.0f,%5.1f,%6.3f,%5.2f,%5.1f,%5.1f,%5.1f,%5.1f,%6.2f,%5.2f,----\n",
			Name,Asset,Algo,
			BarPeriod*TimeFrame,NumMinutes/1440,
			VR(_WFO_Cycles),VR(_WFO_OOS),
			NetProfit,MarginMax,
			DrawDownMax,
			ifelse(DrawDownPercent>0.,min(100,DrawDownPercent),100.),
			100.*DrawDownBars/(Bar-StartBar),
			NumTrades,
			WinRate,
			Obj,
			PFactor,
			(WinTotal-LossTotal)/NumTrades, // Expactancy per trade
			clamp(Return,-999.9,999.9), // Annual return
			ifelse(NetProfit>0.,CAGR,0.), // CAGR
			//WinTotal/fix0(NumWinTotal) - LossTotal/fix0(NumLossTotal),
			clamp(Calmar,-999.9,999.9),
			ifelse(NetProfit>0.,Sharpe,0.), 
			ifelse(NetProfit>0.,ReturnR2,0.));
//_LOG(strf("\n%i: CA %.0f",TotalCycle,CA_Percent);
//_LOG(Line);
		if(*LocalSummary) {
			if(DO_CA || DO_MRC)
				file_appendCSV(LocalSummary,Line,0,1);
			else
				file_append(LocalSummary,Line);
		}
// update CA%, leave rest unchanged
		if (*Summary) {
			if (DO_CA) { // update CA%, leave rest unchanged
				string Content = file_content(Summary);
				if (!Content) return; // Can't read summary
				string Field = strfield(Line,0,N_TF+1);// clip name,asset,algo,tf
				int Len = (intptr_t)Field-(intptr_t)Line;
				string Compare = strmid(Line,0,Len); 
				if (!(Field = strstr(Content,Compare)))
					file_append(Summary,Line); // not found - append new line
				else {
					Field = strfield(Field,0,N_CA);
					memcpy(Field,strf("%4.0f",CA_Percent),4);
					file_write(Summary,Content,0);
				}
			} else {
				file_appendCSV(Summary,Line,0,3); // replace when asset,algo,tf identical
			}
		}
// end of cycles
		if (TotalCycle >= NumTotalCycles) {
			if(*Summary) {
				if(VI(_Criteria))
					file_sortCSV(Summary,VI(_Criteria),3);
				exec("Editor",Summary,0);
			} else
				exec("Editor",LocalSummary,0);
			switch (JobMode) {
			case 2: // irregular profile
				plotChart(0); break;
			case 3: // regular matrix
				var Scale[4]; 
				Scale[0] = OOSMin; Scale[1] = (OOSMax-OOSMin)/max(1,OOSSteps-1);
				Scale[2] = WFOMin; Scale[3] = (WFOMax-WFOMin)/max(1,WFOSteps-1);
				dataChart(1,"Return",HEATMAP|LABELS,Scale);
#ifdef EXPORTMX
				// write the results in a CSV matrix
				string Matrix = (string)zalloc((OOSSteps+1)*(CycleSteps+1)*20);
				strcpy(Matrix,"OOS%\\Cycles,");
				for (int i=1; i<=CycleSteps; i++)
					strcat(Matrix,strf("%3i,",getWFOCycles(i)));
				for (int j=1; j<=OOSSteps; j++) {
					strcat(Matrix,strf("\n%3i,",getOOS(j)));
					for (int i=1; i<=CycleSteps; i++)
						strcat(Matrix,strf("%6.2f,",dataVar(1,j-1,i-1)));
				}
				file_write(strf("Log\\%s_Matrix.csv",Script),Matrix,0);
				exec("Editor",Name,0);
#endif
				break;
			case 5:
				PlotLabels = 2;
				plotHistogram("Original",OriginalResult,StepWidth,sqrt(NumTotalCycles),BLACK);	
				plotHistogram("",0,StepWidth,1,-1);	// plot labels
				print(_MSG,"\n-------------------------------------------");
				print(_MSG,"\nP-Value %.1f%%",PV);
				if (PV <= 2.)
					print(_MSG,"\nResult is significant");
				else if (PV <= 5.)
					print(_MSG,"\nResult is possibly significant");
				else
					print(_MSG,"\nResult insignificant");
				print(_MSG,"\n-------------------------------------------");
				break;
			}
		}
	} else if(strstr(Define,".csv")) // output for comparison
		file_copy(strx(Define,".csv","_out.txt"),"Log\\Eval_out.txt");
	else if(NumJobs <= 1) { // single job
		string Name = strf("Log\\%s.txt",Script);
		exec("Editor",Name,0);
	}
}

DLLFUNC void cleanup()
{
	panel(0,0,0);
	if (JobContents) free(JobContents);
	if (AlgoContents) free(AlgoContents);
	AlgoContents = NULL; 
	JobContents = NULL;
}
