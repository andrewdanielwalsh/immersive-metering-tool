function [loudnessTable, loudnessData] = computeLoudness(audioData, fs, channelMapTable, options)
%COMPUTELOUDNESS Calculate LUFS, LRA, true peak, and loudness history.
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Step 5 loudness analysis for mono, stereo, 5.1, 7.1, 7.1.4,
%   and custom multichannel WAV files.
%
% Requirements:
%   Audio Toolbox is required for integratedLoudness and loudnessMeter.
%
% Inputs:
%   audioData        - Audio samples [numSamples x numChannels]
%   fs               - Sample rate in Hz
%   channelMapTable  - Table from validateChannelMap()
%   options          - Optional struct
%
% Outputs:
%   loudnessTable    - Summary table for program, groups, channels, and sum
%   loudnessData     - Struct containing detailed loudness data

    %% Check Audio Toolbox functions

    if exist("integratedLoudness", "file") ~= 2
        error("computeLoudness:MissingAudioToolbox", ...
            "integratedLoudness was not found. This function requires Audio Toolbox.");
    end

    if exist("loudnessMeter", "file") ~= 2 && exist("loudnessMeter", "class") ~= 8
        error("computeLoudness:MissingAudioToolbox", ...
            "loudnessMeter was not found. This function requires Audio Toolbox.");
    end

    %% Validate audio input

    if nargin < 1 || isempty(audioData)
        error("computeLoudness:InvalidAudioData", ...
            "audioData must be a nonempty numeric matrix.");
    end

    if ~isnumeric(audioData) || ~isreal(audioData)
        error("computeLoudness:InvalidAudioData", ...
            "audioData must be real numeric audio data.");
    end

    if any(~isfinite(audioData(:)))
        error("computeLoudness:InvalidAudioData", ...
            "audioData must not contain NaN or Inf values.");
    end

    if isvector(audioData)
        audioData = audioData(:);
    end

    [numSamples, numChannels] = size(audioData);

    if numSamples < 1 || numChannels < 1
        error("computeLoudness:InvalidAudioData", ...
            "audioData must contain at least one sample and one channel.");
    end

    if nargin < 2 || isempty(fs) || ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error("computeLoudness:InvalidSampleRate", ...
            "fs must be a positive scalar sample rate in Hz.");
    end

    %% Options

    if nargin < 4 || isempty(options)
        options = struct();
    end

    if ~isstruct(options)
        error("computeLoudness:InvalidOptions", ...
            "options must be a struct.");
    end

    options = applyDefaultOptions(options, fs);

    frameSamples = max(256, round(options.FrameDurationSeconds * fs));

    %% Normalize channel map

    channelMapTable = normalizeChannelMap(channelMapTable, numChannels);

    if ~options.IncludeLFEInProgram
        channelMapTable.IncludeInLoudness(channelMapTable.IsLFE) = false;
        channelMapTable.LoudnessWeight(channelMapTable.IsLFE) = 0;
    end

    %% Initialize summary arrays

    MeasurementType = strings(0, 1);
    Name = strings(0, 1);
    ChannelCount = zeros(0, 1);
    Channels = strings(0, 1);
    IntegratedLUFS = zeros(0, 1);
    LoudnessRangeLU = zeros(0, 1);
    TruePeakDBTP = zeros(0, 1);
    MaxMomentaryLUFS = zeros(0, 1);
    MaxShortTermLUFS = zeros(0, 1);
    PLR_dB = zeros(0, 1);
    PSR_dB = zeros(0, 1);
    Notes = strings(0, 1);

    %% Program loudness

    programMask = channelMapTable.IncludeInLoudness & ...
                  channelMapTable.LoudnessWeight > 0;

    if ~any(programMask)
        error("computeLoudness:NoProgramChannels", ...
            "No channels are enabled for program loudness.");
    end

    programChannels = channelMapTable.FileChannel(programMask);
    programLabels = channelMapTable.SpeakerLabel(programMask);
    programWeights = channelMapTable.LoudnessWeight(programMask).';

    programSignal = audioData(:, programChannels);

    [programLUFS, programLRA] = safeIntegratedLoudness(programSignal, fs, programWeights);
    programHistory = measureLoudnessHistory(programSignal, fs, programWeights, frameSamples);

    addSummaryRow( ...
        "Program", ...
        "Full Program", ...
        numel(programChannels), ...
        joinLabels(programLabels), ...
        programLUFS, ...
        programLRA, ...
        programHistory.MaxTruePeakDBTP, ...
        programHistory.MaxMomentaryLUFS, ...
        programHistory.MaxShortTermLUFS, ...
        "Multichannel program loudness using IncludeInLoudness and LoudnessWeight." ...
    );

    %% Group loudness

    groupHistories = struct();

    if options.ComputeGroups
        activeGroups = unique(string(channelMapTable.Group(programMask)));

        for g = 1:numel(activeGroups)
            currentGroup = activeGroups(g);

            if currentGroup == "" || currentGroup == "Unassigned"
                continue;
            end

            groupMask = programMask & string(channelMapTable.Group) == currentGroup;

            if ~any(groupMask)
                continue;
            end

            groupChannels = channelMapTable.FileChannel(groupMask);
            groupLabels = channelMapTable.SpeakerLabel(groupMask);
            groupWeights = channelMapTable.LoudnessWeight(groupMask).';

            groupSignal = audioData(:, groupChannels);

            [groupLUFS, groupLRA] = safeIntegratedLoudness(groupSignal, fs, groupWeights);
            groupHistory = measureLoudnessHistory(groupSignal, fs, groupWeights, frameSamples);

            addSummaryRow( ...
                "Group", ...
                currentGroup, ...
                numel(groupChannels), ...
                joinLabels(groupLabels), ...
                groupLUFS, ...
                groupLRA, ...
                groupHistory.MaxTruePeakDBTP, ...
                groupHistory.MaxMomentaryLUFS, ...
                groupHistory.MaxShortTermLUFS, ...
                "Group loudness using active channels in this speaker group." ...
            );

            safeGroupName = matlab.lang.makeValidName(currentGroup);
            groupHistories.(safeGroupName) = groupHistory;
        end
    end

    %% Per-channel loudness

    perChannelTable = table();
    perChannelHistories = struct();

    if options.ComputePerChannel
        ChannelNumber = (1:numChannels).';
        ChannelLabel = channelMapTable.SpeakerLabel(:);
        ChannelGroup = channelMapTable.Group(:);
        IsLFE = channelMapTable.IsLFE(:);
        IncludeInLoudness = channelMapTable.IncludeInLoudness(:);

        ChannelIntegratedLUFS = NaN(numChannels, 1);
        ChannelLRA = NaN(numChannels, 1);
        ChannelTruePeakDBTP = NaN(numChannels, 1);
        ChannelMaxMomentaryLUFS = NaN(numChannels, 1);
        ChannelMaxShortTermLUFS = NaN(numChannels, 1);

        for ch = 1:numChannels
            x = audioData(:, ch);

            [chLUFS, chLRA] = safeIntegratedLoudness(x, fs, 1);
            chHistory = measureLoudnessHistory(x, fs, 1, frameSamples);

            ChannelIntegratedLUFS(ch) = chLUFS;
            ChannelLRA(ch) = chLRA;
            ChannelTruePeakDBTP(ch) = chHistory.MaxTruePeakDBTP;
            ChannelMaxMomentaryLUFS(ch) = chHistory.MaxMomentaryLUFS;
            ChannelMaxShortTermLUFS(ch) = chHistory.MaxShortTermLUFS;

            addSummaryRow( ...
                "PerChannel", ...
                ChannelLabel(ch), ...
                1, ...
                ChannelLabel(ch), ...
                chLUFS, ...
                chLRA, ...
                chHistory.MaxTruePeakDBTP, ...
                chHistory.MaxMomentaryLUFS, ...
                chHistory.MaxShortTermLUFS, ...
                "Diagnostic mono loudness for this individual WAV channel." ...
            );

            safeChannelName = matlab.lang.makeValidName("Ch" + string(ch) + "_" + ChannelLabel(ch));
            perChannelHistories.(safeChannelName) = chHistory;
        end

        perChannelTable = table( ...
            ChannelNumber, ...
            ChannelLabel, ...
            ChannelGroup, ...
            IsLFE, ...
            IncludeInLoudness, ...
            ChannelIntegratedLUFS, ...
            ChannelLRA, ...
            ChannelTruePeakDBTP, ...
            ChannelMaxMomentaryLUFS, ...
            ChannelMaxShortTermLUFS, ...
            'VariableNames', { ...
                'ChannelNumber', ...
                'ChannelLabel', ...
                'Group', ...
                'IsLFE', ...
                'IncludeInLoudness', ...
                'IntegratedLUFS', ...
                'LoudnessRangeLU', ...
                'TruePeakDBTP', ...
                'MaxMomentaryLUFS', ...
                'MaxShortTermLUFS' ...
            } ...
        );
    end

    %% Summed / downmix loudness

    summedSignal = [];
    summedHistory = struct();

    if options.ComputeSummedDownmix
        weightedProgramSignal = programSignal .* programWeights;
        summedSignal = sum(weightedProgramSignal, 2);

        if options.NormalizeSummedDownmix
            normalizer = sum(abs(programWeights));

            if normalizer > 0
                summedSignal = summedSignal ./ normalizer;
            end
        end

        [summedLUFS, summedLRA] = safeIntegratedLoudness(summedSignal, fs, 1);
        summedHistory = measureLoudnessHistory(summedSignal, fs, 1, frameSamples);

        addSummaryRow( ...
            "SummedDownmix", ...
            "Weighted Sum", ...
            1, ...
            joinLabels(programLabels), ...
            summedLUFS, ...
            summedLRA, ...
            summedHistory.MaxTruePeakDBTP, ...
            summedHistory.MaxMomentaryLUFS, ...
            summedHistory.MaxShortTermLUFS, ...
            "Diagnostic summed/downmixed signal. This is not the same as official multichannel program LUFS." ...
        );
    end

    %% Build final loudness table

    loudnessTable = table( ...
        MeasurementType, ...
        Name, ...
        ChannelCount, ...
        Channels, ...
        IntegratedLUFS, ...
        LoudnessRangeLU, ...
        TruePeakDBTP, ...
        MaxMomentaryLUFS, ...
        MaxShortTermLUFS, ...
        PLR_dB, ...
        PSR_dB, ...
        Notes ...
    );

    %% Build output struct

    loudnessData = struct();

    loudnessData.SampleRate = fs;
    loudnessData.NumSamples = numSamples;
    loudnessData.NumChannels = numChannels;
    loudnessData.ChannelMapTable = channelMapTable;
    loudnessData.Options = options;

    loudnessData.Program = struct();
    loudnessData.Program.SignalChannels = programChannels;
    loudnessData.Program.ChannelLabels = programLabels;
    loudnessData.Program.ChannelWeights = programWeights;
    loudnessData.Program.IntegratedLUFS = programLUFS;
    loudnessData.Program.LoudnessRangeLU = programLRA;
    loudnessData.Program.TruePeakDBTP = programHistory.MaxTruePeakDBTP;
    loudnessData.Program.MaxMomentaryLUFS = programHistory.MaxMomentaryLUFS;
    loudnessData.Program.MaxShortTermLUFS = programHistory.MaxShortTermLUFS;
    loudnessData.Program.History = programHistory;

    loudnessData.Groups = groupHistories;
    loudnessData.PerChannelTable = perChannelTable;
    loudnessData.PerChannelHistories = perChannelHistories;

    loudnessData.SummedDownmix = struct();
    loudnessData.SummedDownmix.Signal = summedSignal;
    loudnessData.SummedDownmix.History = summedHistory;

    %% Nested helper for adding rows to the loudness summary table

    function addSummaryRow(type, rowName, channelCount, channelText, lufs, lra, truePeak, maxMomentary, maxShortTerm, noteText)

        MeasurementType(end + 1, 1) = string(type);
        Name(end + 1, 1) = string(rowName);
        ChannelCount(end + 1, 1) = channelCount;
        Channels(end + 1, 1) = string(channelText);
        IntegratedLUFS(end + 1, 1) = lufs;
        LoudnessRangeLU(end + 1, 1) = lra;
        TruePeakDBTP(end + 1, 1) = truePeak;
        MaxMomentaryLUFS(end + 1, 1) = maxMomentary;
        MaxShortTermLUFS(end + 1, 1) = maxShortTerm;

        if isfinite(truePeak) && isfinite(lufs)
            PLR_dB(end + 1, 1) = truePeak - lufs;
        else
            PLR_dB(end + 1, 1) = NaN;
        end

        if isfinite(truePeak) && isfinite(maxShortTerm)
            PSR_dB(end + 1, 1) = truePeak - maxShortTerm;
        else
            PSR_dB(end + 1, 1) = NaN;
        end

        Notes(end + 1, 1) = string(noteText);
    end

end

%% Local helper functions

function options = applyDefaultOptions(options, fs)
%APPLYDEFAULTOPTIONS Add default loudness options.

    if ~isfield(options, "FrameDurationSeconds") || isempty(options.FrameDurationSeconds)
        options.FrameDurationSeconds = 0.100;
    end

    if ~isfield(options, "ComputePerChannel") || isempty(options.ComputePerChannel)
        options.ComputePerChannel = true;
    end

    if ~isfield(options, "ComputeGroups") || isempty(options.ComputeGroups)
        options.ComputeGroups = true;
    end

    if ~isfield(options, "ComputeSummedDownmix") || isempty(options.ComputeSummedDownmix)
        options.ComputeSummedDownmix = true;
    end

    if ~isfield(options, "NormalizeSummedDownmix") || isempty(options.NormalizeSummedDownmix)
        options.NormalizeSummedDownmix = true;
    end

    if ~isfield(options, "IncludeLFEInProgram") || isempty(options.IncludeLFEInProgram)
        options.IncludeLFEInProgram = false;
    end

    if ~isnumeric(options.FrameDurationSeconds) || ...
            ~isscalar(options.FrameDurationSeconds) || ...
            ~isfinite(options.FrameDurationSeconds) || ...
            options.FrameDurationSeconds <= 0
        error("computeLoudness:InvalidOptions", ...
            "options.FrameDurationSeconds must be a positive scalar.");
    end

    if options.FrameDurationSeconds * fs < 1
        error("computeLoudness:InvalidOptions", ...
            "options.FrameDurationSeconds is too small for the sample rate.");
    end

    options.ComputePerChannel = logical(options.ComputePerChannel);
    options.ComputeGroups = logical(options.ComputeGroups);
    options.ComputeSummedDownmix = logical(options.ComputeSummedDownmix);
    options.NormalizeSummedDownmix = logical(options.NormalizeSummedDownmix);
    options.IncludeLFEInProgram = logical(options.IncludeLFEInProgram);
end

function channelMapTable = normalizeChannelMap(channelMapTable, numChannels)
%NORMALIZECHANNELMAP Make sure the channel map has required columns.

    if nargin < 1 || isempty(channelMapTable)
        FileChannel = (1:numChannels).';
        SpeakerLabel = "Ch" + string(FileChannel);
        Group = repmat("Unknown", numChannels, 1);
        IsLFE = false(numChannels, 1);
        IncludeInLoudness = true(numChannels, 1);
        LoudnessWeight = ones(numChannels, 1);

        channelMapTable = table( ...
            FileChannel, ...
            SpeakerLabel, ...
            Group, ...
            IsLFE, ...
            IncludeInLoudness, ...
            LoudnessWeight ...
        );

        return;
    end

    if ~istable(channelMapTable)
        error("computeLoudness:InvalidChannelMap", ...
            "channelMapTable must be a table from validateChannelMap().");
    end

    if height(channelMapTable) ~= numChannels
        error("computeLoudness:InvalidChannelMap", ...
            "channelMapTable must have one row per audio channel.");
    end

    variableNames = string(channelMapTable.Properties.VariableNames);

    if ~any(variableNames == "FileChannel")
        channelMapTable.FileChannel = (1:numChannels).';
    end

    if ~any(variableNames == "SpeakerLabel")
        channelMapTable.SpeakerLabel = "Ch" + string((1:numChannels).');
    end

    if ~any(variableNames == "Group")
        channelMapTable.Group = repmat("Unknown", numChannels, 1);
    end

    if ~any(variableNames == "IsLFE")
        channelMapTable.IsLFE = false(numChannels, 1);
    end

    if ~any(variableNames == "IncludeInLoudness")
        channelMapTable.IncludeInLoudness = true(numChannels, 1);
    end

    if ~any(variableNames == "LoudnessWeight")
        channelMapTable.LoudnessWeight = ones(numChannels, 1);
    end

    channelMapTable.FileChannel = double(channelMapTable.FileChannel(:));
    channelMapTable.SpeakerLabel = string(channelMapTable.SpeakerLabel(:));
    channelMapTable.Group = string(channelMapTable.Group(:));
    channelMapTable.IsLFE = convertToLogical(channelMapTable.IsLFE);
    channelMapTable.IncludeInLoudness = convertToLogical(channelMapTable.IncludeInLoudness);
    channelMapTable.LoudnessWeight = double(channelMapTable.LoudnessWeight(:));

    if any(~isfinite(channelMapTable.FileChannel)) || ...
            any(channelMapTable.FileChannel < 1) || ...
            any(channelMapTable.FileChannel > numChannels) || ...
            any(mod(channelMapTable.FileChannel, 1) ~= 0)
        error("computeLoudness:InvalidChannelMap", ...
            "FileChannel values must be whole numbers between 1 and the number of audio channels.");
    end

    if any(~isfinite(channelMapTable.LoudnessWeight)) || any(channelMapTable.LoudnessWeight < 0)
        error("computeLoudness:InvalidChannelMap", ...
            "LoudnessWeight values must be finite and nonnegative.");
    end
end

function logicalVector = convertToLogical(inputVector)
%CONVERTTOLOGICAL Convert logical, numeric, or text yes/no values to logical.

    if islogical(inputVector)
        logicalVector = inputVector(:);
        return;
    end

    if isnumeric(inputVector)
        logicalVector = inputVector(:) ~= 0;
        return;
    end

    textValues = lower(string(inputVector(:)));

    logicalVector = textValues == "true" | ...
                    textValues == "yes" | ...
                    textValues == "y" | ...
                    textValues == "1" | ...
                    textValues == "on";
end

function [lufs, lra] = safeIntegratedLoudness(x, fs, weights)
%SAFEINTEGRATEDLOUDNESS Run integratedLoudness and convert empty results to NaN.

    weights = weights(:).';

    try
        [lufs, lra] = integratedLoudness(x, fs, weights);
    catch ME
        error("computeLoudness:IntegratedLoudnessFailed", ...
            "integratedLoudness failed: %s", ME.message);
    end

    if isempty(lufs)
        lufs = NaN;
    end

    if isempty(lra)
        lra = NaN;
    end
end

function history = measureLoudnessHistory(x, fs, weights, frameSamples)
%MEASURELOUDNESSHISTORY Run loudnessMeter frame-by-frame.
%
% Returns a struct containing:
%   history.Table
%   history.TimeSeconds
%   history.MomentaryLUFS
%   history.ShortTermLUFS
%   history.IntegratedLUFS
%   history.LoudnessRangeLU
%   history.TruePeakDBTP
%   history.MaxMomentaryLUFS
%   history.MaxShortTermLUFS
%   history.FinalIntegratedLUFS
%   history.FinalLoudnessRangeLU
%   history.MaxTruePeakDBTP

    weights = weights(:).';

    meter = loudnessMeter( ...
        "SampleRate", fs, ...
        "ChannelWeights", weights);

    numSamples = size(x, 1);
    numFrames = ceil(numSamples / frameSamples);

    TimeSeconds = NaN(numFrames, 1);
    MomentaryLUFS = NaN(numFrames, 1);
    ShortTermLUFS = NaN(numFrames, 1);
    IntegratedLUFS = NaN(numFrames, 1);
    LoudnessRangeLU = NaN(numFrames, 1);
    TruePeakDBTP = NaN(numFrames, 1);

    for frameIndex = 1:numFrames
        firstSample = (frameIndex - 1) * frameSamples + 1;
        lastSample = min(frameIndex * frameSamples, numSamples);

        frame = x(firstSample:lastSample, :);

        [momentary, shortTerm, integrated, rangeValue, peak] = meter(frame);

        TimeSeconds(frameIndex) = lastSample / fs;
        MomentaryLUFS(frameIndex) = lastFiniteScalar(momentary);
        ShortTermLUFS(frameIndex) = lastFiniteScalar(shortTerm);
        IntegratedLUFS(frameIndex) = lastFiniteScalar(integrated);
        LoudnessRangeLU(frameIndex) = lastFiniteScalar(rangeValue);
        TruePeakDBTP(frameIndex) = maxFinite(peak);
    end

    release(meter);

    historyTable = table( ...
        TimeSeconds, ...
        MomentaryLUFS, ...
        ShortTermLUFS, ...
        IntegratedLUFS, ...
        LoudnessRangeLU, ...
        TruePeakDBTP ...
    );

    history = struct();

    history.Table = historyTable;

    history.TimeSeconds = TimeSeconds;
    history.MomentaryLUFS = MomentaryLUFS;
    history.ShortTermLUFS = ShortTermLUFS;
    history.IntegratedLUFS = IntegratedLUFS;
    history.LoudnessRangeLU = LoudnessRangeLU;
    history.TruePeakDBTP = TruePeakDBTP;

    history.MaxMomentaryLUFS = maxFinite(MomentaryLUFS);
    history.MaxShortTermLUFS = maxFinite(ShortTermLUFS);
    history.FinalIntegratedLUFS = lastFiniteScalar(IntegratedLUFS);
    history.FinalLoudnessRangeLU = lastFiniteScalar(LoudnessRangeLU);
    history.MaxTruePeakDBTP = maxFinite(TruePeakDBTP);
end

function value = lastFiniteScalar(x)
%LASTFINITESCALAR Return the last finite scalar from an array.

    x = x(:);
    x = x(isfinite(x));

    if isempty(x)
        value = NaN;
    else
        value = x(end);
    end
end

function value = maxFinite(x)
%MAXFINITE Return the maximum finite value from an array.

    x = x(:);
    x = x(isfinite(x));

    if isempty(x)
        value = NaN;
    else
        value = max(x);
    end
end

function textOut = joinLabels(labels)
%JOINLABELS Join speaker labels into a readable string.

    labels = string(labels(:));

    if isempty(labels)
        textOut = "";
    else
        textOut = strjoin(labels.', ", ");
    end
end