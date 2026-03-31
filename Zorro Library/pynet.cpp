// Python neural function //////////////////////////

inline char* slash(const char* name) { return strxc(name,'\\','/'); }

DLLFUNC var neural(int Status,int Model,int NumSignals,char* Data)
{
	if(!wait(0)) return 0;

// open a Python script with the same name as the strategy script  
	if(Status == NEURAL_INIT) {
		if(!pyStart(strf("%s.py",Script),3)) return 0;
		pyX("neural_init()");
		return 1;
	}

// export batch training samples and call the Python training function
	if(Status == NEURAL_TRAIN) {
		string Path = strf("Data\\signals%i.csv",Core);
		file_write(Path,Data,0);
		pySet("AlgoVar",AlgoVar,8);
		if(!pyX(strf("Result = neural_train(%i,'%s')",Model,slash(Path))))
			return 0;
		return pyVar("Result");
	}

	// predict the target with the Python predict function
	if(Status == NEURAL_PREDICT) {
		pySet("AlgoVar",AlgoVar,8);
		pySet("X",(double*)Data,NumSignals);
		if(!pyX(strf("Result = neural_predict(%i,X)",Model))) {
			static int Do = 3;
			if(Do-- > 0) printf("neural_predict failed");
			return 0;
		}
		var Result = pyVar("Result");
		return Result; 
	}

	// save all trained models  
	if(Status == NEURAL_SAVE) {
		print(TO_ANY,"\nStore %s", strrchr(Data,'\\')+1);
		return pyX(strf("neural_save('%s')", slash(Data)));
	}

	// load all trained models  
	if(Status == NEURAL_LOAD) {
		printf("\nLoading %s", strrchr(Data,'\\')+1);
		int Result = pyX(strf("neural_load('%s')", slash(Data)));
		return Result;
	}

	return 1;
}
