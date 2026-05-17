function spectrogramData = computeSpectrogram3D(audioData, fs, channelMapTable, sourceSelection, options)
%COMPUTESPECTROGRAM3D Compute 2D/3D spectrogram data for the metering tool.
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Step 6 spectrogram engine for mono, stereo, 5.1, 7.1, 7.1.4,
%   and custom multichannel WAV files.
%
% Requirements:
%   Signal Processing Toolbox is required for spectrogram.
%
% Inputs:
%   audioData         - Audio samples [numSamples x numChannels]
%   fs                - Sample rate in Hz
%   channelMapTable   - Table from validateChannelMap()
%   sourceSelection   - Channel, speaker label, group, or source name
%                       Examples:
%                       "L", "R", "C", "LFE"
%                       "Front", "Side", "Rear", "Height"
%                       "Bed", "Program", "Sum", "All"
%                       1, 2, [1 2], etc.
%   options           - Optional struct:
%                       StartTimeSeconds
%                       ViewDurationSeconds
%                       FFTWindowDurationSeconds
%                       OverlapPercent
%                       NFFT
%                       FrequencyLimitsHz
%                       PowerFloorDB
%                       NormalizeCombinedSource
%
% Output:
%   spectrogramData   - Struct containing spectrogram result and metadata

    %% Check required function

    if exist("spectrogram", "file") ~= 2
        error("computeSpectrogram3D:MissingSignalProcessingToolbox", ...
            "spectrogram was not found. This function requires Signal Processing Toolbox.");
    end

    %% Validate audio input

    if nargin < 1 || isempty(audioData)
        error("computeSpectrogram3D:InvalidAudioData", ...
            "audioData must be a nonempty numeric matrix.");
    end

    if ~isnumeric(audioData) || ~isreal(audioData)
        error("computeSpectrogram3D:InvalidAudioData", ...
            "audioData must be real numeric audio data.");
    end

    if any(~isfinite(audioData(:)))
        error("computeSpectrogram3D:InvalidAudioData", ...
            "audioData must not contain NaN or Inf values.");
    end

    if isvector(audioData)
        audioData = audioData(:);
    end

    [numSamples, numChannels] = size(audioData);

    if numSamples < 2 || numChannels < 1
        error("computeSpectrogram3D:InvalidAudioData", ...
            "audioData must contain at least two samples and one channel.");
    end

    %% Validate sample rate

    if nargin < 2 || isempty(fs) || ...
            ~isnumeric(fs) || ~isscalar(fs) || ...
            ~isfinite(fs) || fs <= 0
        error("computeSpectrogram3D:InvalidSampleRate", ...
            "fs must be a positive scalar sample rate in Hz.");
    end

    %% Default channel map if needed

    if nargin < 3 || isempty(channelMapTable)
        channelMapTable = createDefaultChannelMap(numChannels);
    else
        channelMapTable = normalizeChannelMap(channelMapTable, numChannels);
    end

    %% Default source selection

    if nargin < 4 || isempty(sourceSelection)
        sourceSelection = "Program";
    end

    %% Options

    if nargin < 5 || isempty(options)
        options = struct();
    end

    if ~isstruct(options)
        error("computeSpectrogram3D:InvalidOptions", ...
            "options must be a struct.");
    end

    options = applyDefaultOptions(options, fs, numSamples);

    %% Select source audio

    [sourceAudio, selectedChannels, sourceName, sourceNote] = selectSpectrogramSource( ...
        audioData, ...
        channelMapTable, ...
        sourceSelection, ...
        options.NormalizeCombinedSource);

    %% Select time range

    totalDurationSeconds = numSamples / fs;

    startTimeSeconds = max(0, options.StartTimeSeconds);

    if startTimeSeconds >= totalDurationSeconds
        error("computeSpectrogram3D:InvalidTimeRange", ...
            "StartTimeSeconds must be less than the total audio duration.");
    end

    if isinf(options.ViewDurationSeconds)
        endTimeSeconds = totalDurationSeconds;
    else
        endTimeSeconds = min(totalDurationSeconds, startTimeSeconds + options.ViewDurationSeconds);
    end

    startSample = max(1, floor(startTimeSeconds * fs) + 1);
    endSample = min(numSamples, floor(endTimeSeconds * fs));

    if endSample <= startSample
        error("computeSpectrogram3D:InvalidTimeRange", ...
            "The selected time range is too short.");
    end

    x = sourceAudio(startSample:endSample);

    %% FFT/window settings

    windowSamples = round(options.FFTWindowDurationSeconds * fs);

    if windowSamples < 8
        error("computeSpectrogram3D:InvalidFFTWindow", ...
            "FFTWindowDurationSeconds is too small. Use a longer FFT window.");
    end

    if windowSamples > numel(x)
        windowSamples = numel(x);
    end

    overlapSamples = round((options.OverlapPercent / 100) * windowSamples);
    overlapSamples = min(overlapSamples, windowSamples - 1);

    if isempty(options.NFFT)
        nfft = 2^nextpow2(windowSamples);
    else
        nfft = options.NFFT;
    end

    if nfft < windowSamples
        nfft = 2^nextpow2(windowSamples);
    end

    windowVector = createHannWindow(windowSamples);

    %% Compute spectrogram

    [S, F, T, P] = spectrogram( ...
        x, ...
        windowVector, ...
        overlapSamples, ...
        nfft, ...
        fs, ...
        "power");

    powerDB = 10 * log10(P + eps);

    if ~isempty(options.PowerFloorDB)
        powerDB(powerDB < options.PowerFloorDB) = options.PowerFloorDB;
    end

    absoluteTimeSeconds = T + startTimeSeconds;

    %% Apply frequency limits

    frequencyMask = F >= options.FrequencyLimitsHz(1) & F <= options.FrequencyLimitsHz(2);

    F = F(frequencyMask);
    S = S(frequencyMask, :);
    P = P(frequencyMask, :);
    powerDB = powerDB(frequencyMask, :);

    %% Output struct

    spectrogramData = struct();

    spectrogramData.SourceName = sourceName;
    spectrogramData.SourceSelection = sourceSelection;
    spectrogramData.SourceNote = sourceNote;
    spectrogramData.SelectedChannels = selectedChannels;
    spectrogramData.SelectedLabels = channelMapTable.SpeakerLabel(selectedChannels);

    spectrogramData.SampleRate = fs;
    spectrogramData.TotalDurationSeconds = totalDurationSeconds;
    spectrogramData.StartTimeSeconds = startTimeSeconds;
    spectrogramData.EndTimeSeconds = endTimeSeconds;
    spectrogramData.ViewDurationSeconds = endTimeSeconds - startTimeSeconds;

    spectrogramData.WindowSamples = windowSamples;
    spectrogramData.FFTWindowDurationSeconds = windowSamples / fs;
    spectrogramData.OverlapSamples = overlapSamples;
    spectrogramData.OverlapPercent = 100 * overlapSamples / windowSamples;
    spectrogramData.NFFT = nfft;

    spectrogramData.FrequencyHz = F;
    spectrogramData.TimeSeconds = absoluteTimeSeconds;
    spectrogramData.STFT = S;
    spectrogramData.PowerLinear = P;
    spectrogramData.PowerDB = powerDB;

    spectrogramData.Options = options;
end

%% Local helper functions

function options = applyDefaultOptions(options, fs, numSamples)
%APPLYDEFAULTOPTIONS Fill missing spectrogram options.

    totalDurationSeconds = numSamples / fs;

    if ~isfield(options, "StartTimeSeconds") || isempty(options.StartTimeSeconds)
        options.StartTimeSeconds = 0;
    end

    if ~isfield(options, "ViewDurationSeconds") || isempty(options.ViewDurationSeconds)
        options.ViewDurationSeconds = min(10, totalDurationSeconds);
    end

    if ~isfield(options, "FFTWindowDurationSeconds") || isempty(options.FFTWindowDurationSeconds)
        options.FFTWindowDurationSeconds = 0.050;
    end

    if ~isfield(options, "OverlapPercent") || isempty(options.OverlapPercent)
        options.OverlapPercent = 75;
    end

    if ~isfield(options, "NFFT")
        options.NFFT = [];
    end

    if ~isfield(options, "FrequencyLimitsHz") || isempty(options.FrequencyLimitsHz)
        options.FrequencyLimitsHz = [20, min(20000, fs / 2)];
    end

    if ~isfield(options, "PowerFloorDB")
        options.PowerFloorDB = -120;
    end

    if ~isfield(options, "NormalizeCombinedSource") || isempty(options.NormalizeCombinedSource)
        options.NormalizeCombinedSource = true;
    end

    validatePositiveScalar(options.FFTWindowDurationSeconds, "options.FFTWindowDurationSeconds");
    validateFiniteScalar(options.StartTimeSeconds, "options.StartTimeSeconds");
    validatePositiveScalar(options.ViewDurationSeconds, "options.ViewDurationSeconds");

    if options.StartTimeSeconds < 0
        error("computeSpectrogram3D:InvalidOptions", ...
            "options.StartTimeSeconds must be zero or positive.");
    end

    if ~isnumeric(options.OverlapPercent) || ~isscalar(options.OverlapPercent) || ...
            ~isfinite(options.OverlapPercent) || ...
            options.OverlapPercent < 0 || options.OverlapPercent >= 100
        error("computeSpectrogram3D:InvalidOptions", ...
            "options.OverlapPercent must be from 0 to less than 100.");
    end

    if ~isempty(options.NFFT)
        if ~isnumeric(options.NFFT) || ~isscalar(options.NFFT) || ...
                ~isfinite(options.NFFT) || options.NFFT < 8 || mod(options.NFFT, 1) ~= 0
            error("computeSpectrogram3D:InvalidOptions", ...
                "options.NFFT must be an empty value or a positive integer >= 8.");
        end
    end

    if ~isnumeric(options.FrequencyLimitsHz) || numel(options.FrequencyLimitsHz) ~= 2 || ...
            any(~isfinite(options.FrequencyLimitsHz)) || ...
            options.FrequencyLimitsHz(1) < 0 || ...
            options.FrequencyLimitsHz(2) <= options.FrequencyLimitsHz(1)
        error("computeSpectrogram3D:InvalidOptions", ...
            "options.FrequencyLimitsHz must be [low high] in Hz.");
    end

    options.FrequencyLimitsHz = double(options.FrequencyLimitsHz(:)).';
    options.FrequencyLimitsHz(2) = min(options.FrequencyLimitsHz(2), fs / 2);

    if ~isempty(options.PowerFloorDB)
        validateFiniteScalar(options.PowerFloorDB, "options.PowerFloorDB");
    end

    options.NormalizeCombinedSource = logical(options.NormalizeCombinedSource);
end

function [sourceAudio, selectedChannels, sourceName, sourceNote] = selectSpectrogramSource(audioData, channelMapTable, sourceSelection, normalizeCombinedSource)
%SELECTSPECTROGRAMSOURCE Select one channel, group, program, or summed source.

    numChannels = size(audioData, 2);

    if isnumeric(sourceSelection)
        selectedChannels = sourceSelection(:).';

        if isempty(selectedChannels) || ...
                any(~isfinite(selectedChannels)) || ...
                any(selectedChannels < 1) || ...
                any(selectedChannels > numChannels) || ...
                any(mod(selectedChannels, 1) ~= 0)
            error("computeSpectrogram3D:InvalidSourceSelection", ...
                "Numeric sourceSelection must contain valid channel numbers.");
        end

        sourceName = "Channels " + strjoin(string(selectedChannels), ", ");
        sourceNote = "Numeric channel selection.";
    else
        sourceText = lower(strtrim(string(sourceSelection)));

        labelsLower = lower(string(channelMapTable.SpeakerLabel));
        groupsLower = lower(string(channelMapTable.Group));

        selectedChannels = [];

        labelMatch = find(labelsLower == sourceText, 1);

        if ~isempty(labelMatch)
            selectedChannels = channelMapTable.FileChannel(labelMatch);
            sourceName = channelMapTable.SpeakerLabel(labelMatch);
            sourceNote = "Single speaker-label source.";
        else
            switch sourceText
                case {"program", "full program", "full", "all active"}
                    if any(string(channelMapTable.Properties.VariableNames) == "IncludeInSpatial")
                        mask = channelMapTable.IncludeInSpatial;
                    elseif any(string(channelMapTable.Properties.VariableNames) == "IncludeInLoudness")
                        mask = channelMapTable.IncludeInLoudness;
                    else
                        mask = ~channelMapTable.IsLFE;
                    end

                    selectedChannels = channelMapTable.FileChannel(mask);
                    sourceName = "Program";
                    sourceNote = "Combined active non-LFE/program channels.";

                case {"sum", "downmix", "weighted sum", "all"}
                    selectedChannels = 1:numChannels;
                    sourceName = "All Channels Sum";
                    sourceNote = "Combined sum of all file channels.";

                case {"front"}
                    selectedChannels = channelMapTable.FileChannel(groupsLower == "front");
                    sourceName = "Front";
                    sourceNote = "Combined front speaker group.";

                case {"side", "sides", "surround", "surrounds"}
                    selectedChannels = channelMapTable.FileChannel(groupsLower == "side");
                    sourceName = "Side";
                    sourceNote = "Combined side/surround speaker group.";

                case {"rear", "rears"}
                    selectedChannels = channelMapTable.FileChannel(groupsLower == "rear");
                    sourceName = "Rear";
                    sourceNote = "Combined rear speaker group.";

                case {"height", "top", "tops"}
                    selectedChannels = channelMapTable.FileChannel(contains(groupsLower, "height"));
                    sourceName = "Height";
                    sourceNote = "Combined height speaker groups.";

                case {"heightfront", "height front", "top front"}
                    selectedChannels = channelMapTable.FileChannel(groupsLower == "heightfront");
                    sourceName = "Height Front";
                    sourceNote = "Combined front height speakers.";

                case {"heightrear", "height rear", "top rear"}
                    selectedChannels = channelMapTable.FileChannel(groupsLower == "heightrear");
                    sourceName = "Height Rear";
                    sourceNote = "Combined rear height speakers.";

                case {"bed", "bed layer"}
                    selectedChannels = channelMapTable.FileChannel( ...
                        ~contains(groupsLower, "height") & ...
                        groupsLower ~= "lfe" & ...
                        groupsLower ~= "unassigned");
                    sourceName = "Bed";
                    sourceNote = "Combined non-height, non-LFE bed-layer speakers.";

                case {"lfe", "sub"}
                    selectedChannels = channelMapTable.FileChannel(channelMapTable.IsLFE);
                    sourceName = "LFE";
                    sourceNote = "LFE channel only.";

                otherwise
                    groupMatch = groupsLower == sourceText;

                    if any(groupMatch)
                        selectedChannels = channelMapTable.FileChannel(groupMatch);
                        sourceName = string(sourceSelection);
                        sourceNote = "Matched speaker group.";
                    else
                        error("computeSpectrogram3D:InvalidSourceSelection", ...
                            "sourceSelection was not recognized. Use a channel number, speaker label, group, Program, Sum, Bed, Height, or LFE.");
                    end
            end
        end
    end

    selectedChannels = selectedChannels(:).';

    if isempty(selectedChannels)
        error("computeSpectrogram3D:EmptySourceSelection", ...
            "The selected source contains no channels.");
    end

    selectedChannels = unique(selectedChannels, "stable");

    sourceMatrix = audioData(:, selectedChannels);
    sourceAudio = sum(sourceMatrix, 2);

    if normalizeCombinedSource && numel(selectedChannels) > 1
        sourceAudio = sourceAudio ./ numel(selectedChannels);
    end
end

function channelMapTable = createDefaultChannelMap(numChannels)
%CREATEDEFAULTCHANNELMAP Create generic map if none is supplied.

    FileChannel = (1:numChannels).';
    SpeakerLabel = "Ch" + string(FileChannel);
    Group = repmat("Unknown", numChannels, 1);
    IsLFE = false(numChannels, 1);
    IncludeInLoudness = true(numChannels, 1);
    IncludeInSpatial = true(numChannels, 1);

    channelMapTable = table( ...
        FileChannel, ...
        SpeakerLabel, ...
        Group, ...
        IsLFE, ...
        IncludeInLoudness, ...
        IncludeInSpatial);
end

function channelMapTable = normalizeChannelMap(channelMapTable, numChannels)
%NORMALIZECHANNELMAP Ensure required channel map columns exist.

    if ~istable(channelMapTable)
        error("computeSpectrogram3D:InvalidChannelMap", ...
            "channelMapTable must be a MATLAB table.");
    end

    if height(channelMapTable) ~= numChannels
        error("computeSpectrogram3D:InvalidChannelMap", ...
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

    if ~any(variableNames == "IncludeInSpatial")
        channelMapTable.IncludeInSpatial = true(numChannels, 1);
    end

    channelMapTable.FileChannel = double(channelMapTable.FileChannel(:));
    channelMapTable.SpeakerLabel = string(channelMapTable.SpeakerLabel(:));
    channelMapTable.Group = string(channelMapTable.Group(:));
    channelMapTable.IsLFE = convertToLogical(channelMapTable.IsLFE);
    channelMapTable.IncludeInLoudness = convertToLogical(channelMapTable.IncludeInLoudness);
    channelMapTable.IncludeInSpatial = convertToLogical(channelMapTable.IncludeInSpatial);

    if any(~isfinite(channelMapTable.FileChannel)) || ...
            any(channelMapTable.FileChannel < 1) || ...
            any(channelMapTable.FileChannel > numChannels) || ...
            any(mod(channelMapTable.FileChannel, 1) ~= 0)
        error("computeSpectrogram3D:InvalidChannelMap", ...
            "FileChannel values must be whole numbers from 1 to the number of channels.");
    end
end

function logicalVector = convertToLogical(inputVector)
%CONVERTTOLOGICAL Convert logical, numeric, or yes/no text to logical.

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

function windowVector = createHannWindow(windowSamples)
%CREATEHANNWINDOW Create a periodic Hann window without needing hann().

    n = (0:windowSamples-1).';
    windowVector = 0.5 - 0.5 * cos(2*pi*n/windowSamples);
end

function validatePositiveScalar(value, name)
%VALIDATEPOSITIVESCALAR Validate a positive scalar.

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error("computeSpectrogram3D:InvalidOptions", ...
            "%s must be a positive scalar.", name);
    end
end

function validateFiniteScalar(value, name)
%VALIDATEFINITESCALAR Validate a finite scalar.

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error("computeSpectrogram3D:InvalidOptions", ...
            "%s must be a finite scalar.", name);
    end
end