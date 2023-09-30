%% Automated
% Load all data
% Find available datasets (always using dates as folders)
clear DateOpt
% %dd = arrayfun(@(X) fullfile(DataDir{DataDir2Use(X)},MiceOpt{X},'*-*'),1:length(MiceOpt),'UniformOutput',0);
DateOpt = arrayfun(@(X) dir(fullfile(DataDir{DataDir2Use(X)},MiceOpt{X},'*-*')),1:length(MiceOpt),'UniformOutput',0); % DataDir2Use = server
DateOpt = cellfun(@(X) X([X.isdir]),DateOpt,'UniformOutput',0);
DateOpt = cellfun(@(X) {X.name},DateOpt,'UniformOutput',0);

LogError = {}; % Keep track of which runs didn't work
for midx = 1:length(MiceOpt)
    %% Loading data from kilosort/phy easily
    if ~isempty(KilosortDir)
        myKsDir = fullfile(KilosortDir,MiceOpt{midx});
        subksdirs = dir(fullfile(myKsDir,'**','Probe*')); %This changed because now I suddenly had 2 probes per recording
        if length(subksdirs)<1
            clear subksdirs
            subksdirs.folder = myKsDir; %Should be a struct array
            subksdirs.name = 'Probe0';
        end
        ProbeOpt = (unique({subksdirs(:).name}));

        myKsDir = fullfile(KilosortDir,MiceOpt{midx});
        % Check for multiple subfolders?
        subsesopt = dir(fullfile(myKsDir,'**','channel_positions.npy'));
        subsesopt=arrayfun(@(X) subsesopt(X).folder,1:length(subsesopt),'Uni',0);
        % Remove anything that contains the name 'noise'
        subsesopt(cellfun(@(X) contains(X,'NOISE'),subsesopt)) = [];
    else
        myKsDir = fullfile(DataDir{DataDir2Use(midx)},MiceOpt{midx});
        subsesopt = [];
        for did = 1:length(DateOpt{midx})
            disp(['Finding all pyKS directories in ' myKsDir ', ' DateOpt{midx}{did}])
            tmpfiles = dir(fullfile(myKsDir,DateOpt{midx}{did},'**','pyKS'));
            tmpfiles(cellfun(@(X) ismember(X,{'.','..'}),{tmpfiles(:).name})) = [];
            % Conver to string
            tmpfiles = arrayfun(@(X) fullfile(tmpfiles(X).folder,tmpfiles(X).name),1:length(tmpfiles),'uni',0);
            subsesopt = [subsesopt, tmpfiles];
        end
    end

    if isempty(subsesopt)
        display(['No data found for ' MiceOpt{midx} ', continue...'])
        continue
    end

    if strcmp(RecordingType{midx},'Chronic')
        if ~PrepareClusInfoparams.RunPyKSChronicStitched %MatchUnitsAcrossDays
            disp('Unit matching in Matlab')
            subsesopt(cell2mat(cellfun(@(X) any(strfind(X,'Chronic')),subsesopt,'UniformOutput',0))) = []; %Use separate days and match units via matlab script
        else
            disp('Using chronic pyks option')
            subsesopt = subsesopt(cell2mat(cellfun(@(X) any(strfind(X,'Chronic')),subsesopt,'UniformOutput',0))); %Use chronic output from pyks
        end
    end

    AllKiloSortPaths = subsesopt;

    %% Create saving directory
    clear params
    if ~exist(fullfile(SaveDir,MiceOpt{midx}))
        mkdir(fullfile(SaveDir,MiceOpt{midx}))
    end
    if isempty(subsesopt)
        disp(['No data found for ' MiceOpt{midx}])
        continue
    end

    %% Prepare cluster information
    PrepareClusInfoparams = PrepareClusInfo(AllKiloSortPaths,PrepareClusInfoparams);
    PrepareClusInfoparams.RecType = RecordingType{midx};%

    % Remove empty ones
    EmptyFolders = find(cellfun(@isempty,PrepareClusInfoparams.AllChannelPos));
    AllKiloSortPaths(EmptyFolders) = [];
    PrepareClusInfoparams.AllChannelPos(EmptyFolders) = [];
    PrepareClusInfoparams.AllProbeSN(EmptyFolders) = [];
    PrepareClusInfoparams.RawDataPaths(EmptyFolders) = [];

    %% Might want to run UM for separate IMRO tables & Probes (although UM can handle running all at the same time and takes position into account)
    if ~PrepareClusInfoparams.separateIMRO
        RunSet = ones(1,length(AllKiloSortPaths)); %Run everything at the same time
        nRuns = 1;
    else
        % Extract different IMRO tables
        channelpositionMatrix = cat(3,PrepareClusInfoparams.AllChannelPos{:});
        [UCHanOpt,~,idIMRO] = unique(reshape(channelpositionMatrix,size(channelpositionMatrix,1)*size(channelpositionMatrix,2),[])','rows','stable');
        UCHanOpt = reshape(UCHanOpt',size(channelpositionMatrix,1),size(channelpositionMatrix,2),[]);

        % Extract unique probes used
        [ProbeOpt,~,idProbe]  = unique([PrepareClusInfoparams.AllProbeSN{:}]);
        PosComb = combvec(1:length(ProbeOpt),1:size(UCHanOpt,3)); % Possible combinations Probe X IMRO
        % Assign a number to each KS path related to PosComb
        RunSet = nan(1,length(AllKiloSortPaths));
        for ksid = 1:length(AllKiloSortPaths)
            RunSet(ksid) = find(PosComb(2,:)==idIMRO(ksid) & PosComb(1,:)==idProbe(ksid));
        end
        nRuns = length(PosComb);
    end

    ORIParams = PrepareClusInfoparams; % RESET

    %% Run UnitMatch
    for runid = 20:nRuns
        try
            PrepareClusInfoparams = ORIParams; % RESET
            idx = find(RunSet==runid);
            if isempty(idx)
                continue
            end
            if ~PrepareClusInfoparams.separateIMRO
                PrepareClusInfoparams.SaveDir = fullfile(SaveDir,MiceOpt{midx},'AllProbes','AllIMRO');
            else
                PrepareClusInfoparams.SaveDir = fullfile(SaveDir,MiceOpt{midx},['Probe' num2str(PosComb(1,runid)-1)],['IMRO_' num2str(PosComb(2,runid))]);
                PrepareClusInfoparams.AllChannelPos = PrepareClusInfoparams.AllChannelPos(idx);
                PrepareClusInfoparams.AllProbeSN = PrepareClusInfoparams.AllProbeSN(idx);
                PrepareClusInfoparams.RawDataPaths = PrepareClusInfoparams.RawDataPaths(idx);
            end

            UnitMatchExist = dir(fullfile(PrepareClusInfoparams.SaveDir,'**','UnitMatch.mat'));

            if isempty(UnitMatchExist) || PrepareClusInfoparams.RedoUnitMatch

                %% Evaluate (within unit ID cross-v alidation)
                UMparam = RunUnitMatch(AllKiloSortPaths(idx),PrepareClusInfoparams);

                if isfield(UMparam,'Error')
                    continue
                end

                %% Evaluate (within unit ID cross-validation)
                EvaluatingUnitMatch(UMparam.SaveDir);

                %% Figures
                if UMparam.MakePlotsOfPairs
                    DrawBlind = 0; %1 for blind drawing (for manual judging of pairs)
                    DrawPairsUnitMatch(UMparam.SaveDir,DrawBlind);
                    if UMparam.GUI
                        FigureFlick(UMparam.SaveDir)
                        pause
                    end
                end

                %% QM
                try
                    QualityMetricsROCs(UMparam.SaveDir);
                catch ME
                    disp(['Couldn''t do Quality metrics for ' MiceOpt{midx}])
                end

            else
                UMparam = PrepareClusInfoparams;
            end
            %% Function analysis
            UMparam.SaveDir = fullfile(PrepareClusInfoparams.SaveDir,'UnitMatch');
            ComputeFunctionalScores(UMparam.SaveDir)
            %%
            disp(['Preprocessed data for ' MiceOpt{midx} ' run  ' num2str(runid) '/' num2str(nRuns)])
        catch ME
            disp([MiceOpt{midx} ' run  ' num2str(runid) '/' num2str(nRuns) ' crashed... continue with others'])

            LogError = {LogError{:} [MiceOpt{midx} '_run' num2str(runid)]};
        end


    end
end
%
