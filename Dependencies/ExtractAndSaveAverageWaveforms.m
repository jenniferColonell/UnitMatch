function ExtractAndSaveAverageWaveforms(clusinfo,param,sp)
%% Called by UnitMatch, but can also be used on its own to save two averaged waveforms per unit per session

%% Read in from param
RedoExtraction = param.RedoExtraction; % Raw waveform and parameter extraction
AllDecompPaths = param.AllDecompPaths;
AllRawPaths = param.AllRawPaths;
param.nChannels = length(param.channelpos)+1; %First assume there's a sync channel as well.
sampleamount = param.sampleamount; %500; % Nr. waveforms to include
spikeWidth = param.spikeWidth; %83; % in sample space (time)
halfWidth = floor(spikeWidth/2);
UseBombCelRawWav = param.UseBombCelRawWav; % If Bombcell was also applied on this dataset, it's faster to read in the raw waveforms extracted by Bombcell
SaveDir = param.SaveDir;
%% Extract all cluster info
AllClusterIDs = clusinfo.cluster_id;
UniqueID = 1:length(AllClusterIDs); % Initial assumption: All clusters are unique
Good_Idx = find(clusinfo.Good_ID); %Only care about good units at this point
GoodRecSesID = clusinfo.RecSesID(Good_Idx);

% Define day stucture
recsesAll = clusinfo.RecSesID;
nclus = length(Good_Idx);
ndays = length(unique(recsesAll));
OriSessionSwitch = cell2mat(arrayfun(@(X) find(recsesAll==X,1,'first'),1:ndays,'Uni',0));
OriSessionSwitch = [OriSessionSwitch nclus+1];

%% Actual extraction
dataTypeNBytes = numel(typecast(cast(0, 'uint16'), 'uint8')); % Define datatype

timercounter = tic;
fprintf(1,'Extracting raw waveforms. Progress: %3d%%',0)
pathparts = strsplit(AllDecompPaths{GoodRecSesID(1)},'\');
rawdatapath = dir(fullfile('\\',pathparts{1:end-1}));
if isempty(rawdatapath)
    rawdatapath = dir(fullfile(pathparts{1:end-1}));
end
if exist(fullfile(SaveDir,'UnitMatchWaveforms',['Unit' num2str(UniqueID(Good_Idx(1))) '_RawSpikes.mat'])) && RedoExtraction
    delete(fullfile(SaveDir,'UnitMatchWaveforms','*'))
end

Currentlyloaded = 0;
for uid = 1:nclus
    fprintf(1,'\b\b\b\b%3.0f%%',uid/nclus*100)
    if UseBombCelRawWav
        if exist(fullfile(SaveDir,'UnitMatchWaveforms',['Unit' num2str(UniqueID(Good_Idx(uid))) '_RawSpikes.mat'])) && ~RedoExtraction
            continue
        else
            tmppath = dir(fullfile(param.KSDir(GoodRecSesID(uid)).folder,param.KSDir(GoodRecSesID(uid)).name,'**','RawWaveforms*'));
            spikeMap = readNPY(fullfile(tmppath.folder,tmppath.name,['Unit' num2str(UniqueID(Good_Idx(uid))-OriSessionSwitch(GoodRecSesID(uid))+1) '_RawSpikes.npy']));            
        end
    else
        pathparts = strsplit(AllDecompPaths{GoodRecSesID(uid)},'\');
        rawdatapath = dir(fullfile('\\',pathparts{1:end-1}));
        if isempty(rawdatapath)
            rawdatapath = dir(fullfile(pathparts{1:end-1}));
        end
        if exist(fullfile(SaveDir,'UnitMatchWaveforms',['Unit' num2str(UniqueID(Good_Idx(uid))) '_RawSpikes.mat'])) && ~RedoExtraction
            continue
        else
            if ~(GoodRecSesID(uid) == Currentlyloaded) % Only load new memmap if not already loaded
                % Map the data
                clear memMapData
                spikeFile = dir(AllDecompPaths{GoodRecSesID(uid)});
                try %hacky way of figuring out if sync channel present or not
                    n_samples = spikeFile.bytes / (param.nChannels * dataTypeNBytes);
                    nChannels = param.nChannels - 1; % Last channel is sync, ignore for now
                    ap_data = memmapfile(AllDecompPaths{GoodRecSesID(uid)}, 'Format', {'int16', [param.nChannels, n_samples], 'data'});
                catch
                    nChannels = param.nChannels - 1;
                    n_samples = spikeFile.bytes / (nChannels * dataTypeNBytes);
                    ap_data = memmapfile(AllDecompPaths{GoodRecSesID(uid)}, 'Format', {'int16', [nChannels, n_samples], 'data'});
                end
                memMapData = ap_data.Data.data;
                Currentlyloaded = GoodRecSesID(uid);
            end

            % Spike samples
            idx1=(sp.st(sp.spikeTemplates == AllClusterIDs(Good_Idx(uid)) & sp.RecSes == GoodRecSesID(uid)).*round(sp.sample_rate));  % Spike times in samples;

            %Extract raw waveforms on the fly - % Unit uid
            try
                spikeIndicestmp = sort(datasample(idx1,sampleamount,'replace',false));
            catch ME
                spikeIndicestmp = idx1;
            end
            spikeMap = nan(spikeWidth,nChannels,sampleamount);
            for iSpike = 1:length(spikeIndicestmp)
                thisSpikeIdx = int32(spikeIndicestmp(iSpike));
                if thisSpikeIdx > halfWidth && (thisSpikeIdx + halfWidth) < size(memMapData,2) % check that it's not out of bounds
                    tmp = smoothdata(double(memMapData(1:nChannels,thisSpikeIdx-halfWidth:thisSpikeIdx+halfWidth)),2,'gaussian',5);
                    tmp = (tmp - mean(tmp(:,1:20),2))';
                    tmp(:,end+1:nChannels) = nan(size(tmp,1),nChannels-size(tmp,2));
                    % Subtract first 10 samples to level spikes
                    spikeMap(:,:,iSpike) = tmp;
                end
            end
        end
        %Actual number of wavefroms
        nwavs = sum(sum(~isnan(nanmean(spikeMap,2)),1) == spikeWidth); % Actual number of waves
        for cv = 1:2
            if cv==1
                wavidx = floor(1:nwavs/2);
            else
                wavidx = floor(nwavs/2+1:nwavs);
            end
            spikeMapAvg(:,:,cv) = nanmean(spikeMap(:,:,wavidx),3);
        end
        spikeMap = spikeMapAvg;
        clear spikeMapAvg
    end

    % Detrending
    spikeMap = permute(spikeMap,[2,1,3]); %detrend works over columns
    spikeMap = detrend(spikeMap,1); % Detrend (linearly) to be on the safe side. OVER TIME!
    spikeMap = permute(spikeMap,[2,1,3]);  % Put back in order
    if ~exist(fullfile(SaveDir,'UnitMatchWaveforms'))
        mkdir(fullfile(SaveDir,'UnitMatchWaveforms'))
    end
    save(fullfile(SaveDir,'UnitMatchWaveforms',['Unit' num2str(UniqueID(Good_Idx(uid))) '_RawSpikes.mat']),'spikeMap')
end


fprintf('\n')
disp(['Extracting raw waveforms took ' num2str(round(toc(timercounter)./60)) ' minutes for ' num2str(nclus) ' units'])
