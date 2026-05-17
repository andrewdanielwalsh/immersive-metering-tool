function spatialData = computeSpatialEnergy(audioData, fs, channelMapTable, options)
%COMPUTESPATIALENERGY Estimate spatial energy distribution for multichannel audio.
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Step 7 - Basic spatial field analysis for mono, stereo, 5.1, 7.1,
%   7.1.4, and custom multichannel WAV files.
%
% This function estimates a mix-space spatial centroid over time using:
%   - channel energy
%   - speaker azimuth
%   - speaker elevation
%
% Important:
%   This is not room acoustics yet. It estimates where the mix energy is
%   positioned based on speaker-channel activity and speaker layout.
%
% Inputs:
%   audioData        - Audio samples [numSamples x numChannels]
%   fs               - Sample rate in Hz
%   channelMapTable  - Table from validateChannelMap()
%   options          - Optional struct:
%                      FrameDurationSeconds
%                      HopDurationSeconds
%                      IncludeLFEInSpatial
%                      EnergyFloorDBFS
%
% Output:
%   spatialData      - Struct containing frame table, group table,
%                      channel table, centroid history, and speaker vectors

    %% Validate audio

    if nargin < 1 || isempty(audioData)
        error("computeSpatialEnergy:InvalidAudioData", ...
            "audioData must be a nonempty numeric matrix.");
    end

    if ~isnumeric(audioData) || ~isreal(audioData)
        error("computeSpatialEnergy:InvalidAudioData", ...
            "audioData must be real numeric audio data.");
    end

    if any(~isfinite(audioData(:)))
        error("computeSpatialEnergy:InvalidAudioData", ...
            "audioData must not contain NaN or Inf values.");
    end

    if isvector(audioData)
        audioData = audioData(:);
    end

    [numSamples, numChannels] = size(audioData);

    if numSamples < 1 || numChannels < 1
        error("computeSpatialEnergy:InvalidAudioData", ...
            "audioData must contain at least one sample and one channel.");
    end

    %% Validate sample rate

    if nargin < 2 || isempty(fs) || ~isnumeric(fs) || ...
            ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error("computeSpatialEnergy:InvalidSampleRate", ...
            "fs must be a positive scalar sample rate in Hz.");
    end

    %% Validate channel map

    if nargin < 3 || isempty(channelMapTable)
        channelMapTable = createDefaultChannelMap(numChannels);
    else
        channelMapTable = normalizeChannelMap(channelMapTable, numChannels);
    end

    %% Options

    if nargin < 4 || isempty(options)
        options = struct();
    end

    if ~isstruct(options)
        error("computeSpatialEnergy:InvalidOptions", ...
            "options must be a struct.");
    end

    options = applyDefaultOptions(options);

    frameSamples = max(1, round(options.FrameDurationSeconds * fs));
    hopSamples = max(1, round(options.HopDurationSeconds * fs));

    if frameSamples > numSamples
        frameSamples = numSamples;
    end

    if hopSamples > frameSamples
        hopSamples = frameSamples;
    end

    numFrames = floor((numSamples - frameSamples) / hopSamples) + 1;

    %% Speaker vectors from azimuth/elevation

    az = deg2rad(channelMapTable.AzimuthDeg);
    el = deg2rad(channelMapTable.ElevationDeg);

    speakerX = cos(el) .* sin(az);
    speakerY = cos(el) .* cos(az);
    speakerZ = sin(el);

    speakerVectors = [speakerX, speakerY, speakerZ];

    %% Active channels for spatial centroid

    activeMask = channelMapTable.IncludeInSpatial;

    if ~options.IncludeLFEInSpatial
        activeMask(channelMapTable.IsLFE) = false;
    end

    activeMask = activeMask & ...
        isfinite(channelMapTable.AzimuthDeg) & ...
        isfinite(channelMapTable.ElevationDeg);

    activeChannels = channelMapTable.FileChannel(activeMask);

    if isempty(activeChannels)
        error("computeSpatialEnergy:NoActiveSpatialChannels", ...
            "No channels are active for spatial analysis.");
    end

    activeVectors = speakerVectors(activeMask, :);

    %% Preallocate frame results

    TimeSeconds = NaN(numFrames, 1);
    TotalEnergy = NaN(numFrames, 1);
    TotalEnergyDBFS = NaN(numFrames, 1);

    CentroidX = NaN(numFrames, 1);
    CentroidY = NaN(numFrames, 1);
    CentroidZ = NaN(numFrames, 1);
    CentroidRadius = NaN(numFrames, 1);
    CentroidAzimuthDeg = NaN(numFrames, 1);
    CentroidElevationDeg = NaN(numFrames, 1);

    FrontPercent = NaN(numFrames, 1);
    SidePercent = NaN(numFrames, 1);
    RearPercent = NaN(numFrames, 1);
    HeightPercent = NaN(numFrames, 1);
    BedPercent = NaN(numFrames, 1);
    LFEPercent = NaN(numFrames, 1);

    LeftPercent = NaN(numFrames, 1);
    RightPercent = NaN(numFrames, 1);
    CenterPercent = NaN(numFrames, 1);

    channelEnergyByFrame = NaN(numFrames, numChannels);

    groupsLower = lower(string(channelMapTable.Group));
    labelsLower = lower(string(channelMapTable.SpeakerLabel));

    %% Frame analysis

    for frameIndex = 1:numFrames
        firstSample = (frameIndex - 1) * hopSamples + 1;
        lastSample = firstSample + frameSamples - 1;

        frame = audioData(firstSample:lastSample, :);

        channelEnergy = mean(frame.^2, 1);
        channelEnergyByFrame(frameIndex, :) = channelEnergy;

        activeEnergy = channelEnergy(activeChannels);

        frameTotalEnergy = sum(activeEnergy);
        TotalEnergy(frameIndex) = frameTotalEnergy;
        TotalEnergyDBFS(frameIndex) = 10 * log10(frameTotalEnergy + eps);

        TimeSeconds(frameIndex) = (firstSample + lastSample) / (2 * fs);

        if frameTotalEnergy > 0
            weightedVector = activeEnergy * activeVectors;
            centroid = weightedVector ./ frameTotalEnergy;

            CentroidX(frameIndex) = centroid(1);
            CentroidY(frameIndex) = centroid(2);
            CentroidZ(frameIndex) = centroid(3);

            radius = norm(centroid);

            CentroidRadius(frameIndex) = radius;
            CentroidAzimuthDeg(frameIndex) = atan2d(centroid(1), centroid(2));

            horizontalMagnitude = sqrt(centroid(1)^2 + centroid(2)^2);
            CentroidElevationDeg(frameIndex) = atan2d(centroid(3), horizontalMagnitude);
        end

        allEnergyTotal = sum(channelEnergy) + eps;

        frontEnergy = sum(channelEnergy(groupsLower == "front"));
        sideEnergy = sum(channelEnergy(groupsLower == "side"));
        rearEnergy = sum(channelEnergy(groupsLower == "rear"));
        heightEnergy = sum(channelEnergy(contains(groupsLower, "height")));
        lfeEnergy = sum(channelEnergy(channelMapTable.IsLFE));

        bedMask = ~contains(groupsLower, "height") & ...
                  groupsLower ~= "lfe" & ...
                  groupsLower ~= "unassigned";

        bedEnergy = sum(channelEnergy(bedMask));

        leftMask = startsWith(labelsLower, "l") & ~channelMapTable.IsLFE;
        rightMask = startsWith(labelsLower, "r") & ~channelMapTable.IsLFE;
        centerMask = labelsLower == "c" | labelsLower == "m" | labelsLower == "mono";

        leftEnergy = sum(channelEnergy(leftMask));
        rightEnergy = sum(channelEnergy(rightMask));
        centerEnergy = sum(channelEnergy(centerMask));

        FrontPercent(frameIndex) = 100 * frontEnergy / allEnergyTotal;
        SidePercent(frameIndex) = 100 * sideEnergy / allEnergyTotal;
        RearPercent(frameIndex) = 100 * rearEnergy / allEnergyTotal;
        HeightPercent(frameIndex) = 100 * heightEnergy / allEnergyTotal;
        BedPercent(frameIndex) = 100 * bedEnergy / allEnergyTotal;
        LFEPercent(frameIndex) = 100 * lfeEnergy / allEnergyTotal;

        LeftPercent(frameIndex) = 100 * leftEnergy / allEnergyTotal;
        RightPercent(frameIndex) = 100 * rightEnergy / allEnergyTotal;
        CenterPercent(frameIndex) = 100 * centerEnergy / allEnergyTotal;
    end

    %% Frame table

    frameTable = table( ...
        TimeSeconds, ...
        TotalEnergy, ...
        TotalEnergyDBFS, ...
        CentroidX, ...
        CentroidY, ...
        CentroidZ, ...
        CentroidRadius, ...
        CentroidAzimuthDeg, ...
        CentroidElevationDeg, ...
        FrontPercent, ...
        SidePercent, ...
        RearPercent, ...
        HeightPercent, ...
        BedPercent, ...
        LFEPercent, ...
        LeftPercent, ...
        RightPercent, ...
        CenterPercent);

    %% Channel summary table

    meanChannelEnergy = mean(channelEnergyByFrame, 1).';
    meanChannelEnergyDBFS = 10 * log10(meanChannelEnergy + eps);

    totalMeanEnergy = sum(meanChannelEnergy) + eps;
    channelEnergyPercent = 100 * meanChannelEnergy ./ totalMeanEnergy;

    channelTable = table( ...
        channelMapTable.FileChannel(:), ...
        channelMapTable.SpeakerLabel(:), ...
        channelMapTable.Group(:), ...
        channelMapTable.IsLFE(:), ...
        channelMapTable.IncludeInSpatial(:), ...
        channelMapTable.AzimuthDeg(:), ...
        channelMapTable.ElevationDeg(:), ...
        speakerX(:), ...
        speakerY(:), ...
        speakerZ(:), ...
        meanChannelEnergy, ...
        meanChannelEnergyDBFS, ...
        channelEnergyPercent, ...
        'VariableNames', { ...
            'FileChannel', ...
            'SpeakerLabel', ...
            'Group', ...
            'IsLFE', ...
            'IncludeInSpatial', ...
            'AzimuthDeg', ...
            'ElevationDeg', ...
            'X', ...
            'Y', ...
            'Z', ...
            'MeanEnergy', ...
            'MeanEnergyDBFS', ...
            'EnergyPercent' ...
        });

    %% Group summary table

    groupTable = buildGroupSummaryTable(channelTable);

    %% Overall summary

    summary = struct();

    summary.MeanCentroidX = mean(CentroidX, "omitnan");
    summary.MeanCentroidY = mean(CentroidY, "omitnan");
    summary.MeanCentroidZ = mean(CentroidZ, "omitnan");
    summary.MeanCentroidRadius = mean(CentroidRadius, "omitnan");
    summary.MeanCentroidAzimuthDeg = mean(CentroidAzimuthDeg, "omitnan");
    summary.MeanCentroidElevationDeg = mean(CentroidElevationDeg, "omitnan");

    summary.MeanFrontPercent = mean(FrontPercent, "omitnan");
    summary.MeanSidePercent = mean(SidePercent, "omitnan");
    summary.MeanRearPercent = mean(RearPercent, "omitnan");
    summary.MeanHeightPercent = mean(HeightPercent, "omitnan");
    summary.MeanBedPercent = mean(BedPercent, "omitnan");
    summary.MeanLFEPercent = mean(LFEPercent, "omitnan");

    summary.MeanLeftPercent = mean(LeftPercent, "omitnan");
    summary.MeanRightPercent = mean(RightPercent, "omitnan");
    summary.MeanCenterPercent = mean(CenterPercent, "omitnan");

    summary.LeftRightBalancePercent = summary.MeanRightPercent - summary.MeanLeftPercent;
    summary.HeightBedBalancePercent = summary.MeanHeightPercent - summary.MeanBedPercent;
    summary.FrontRearBalancePercent = summary.MeanFrontPercent - summary.MeanRearPercent;

    %% Output struct

    spatialData = struct();

    spatialData.SampleRate = fs;
    spatialData.NumSamples = numSamples;
    spatialData.NumChannels = numChannels;
    spatialData.FrameSamples = frameSamples;
    spatialData.HopSamples = hopSamples;
    spatialData.FrameDurationSeconds = frameSamples / fs;
    spatialData.HopDurationSeconds = hopSamples / fs;
    spatialData.NumFrames = numFrames;

    spatialData.ChannelMapTable = channelMapTable;
    spatialData.ActiveChannels = activeChannels;
    spatialData.ActiveLabels = channelMapTable.SpeakerLabel(activeMask);

    spatialData.SpeakerVectors = speakerVectors;
    spatialData.FrameTable = frameTable;
    spatialData.ChannelTable = channelTable;
    spatialData.GroupTable = groupTable;
    spatialData.ChannelEnergyByFrame = channelEnergyByFrame;
    spatialData.Summary = summary;
    spatialData.Options = options;
end

%% Helper functions

function options = applyDefaultOptions(options)

    if ~isfield(options, "FrameDurationSeconds") || isempty(options.FrameDurationSeconds)
        options.FrameDurationSeconds = 0.100;
    end

    if ~isfield(options, "HopDurationSeconds") || isempty(options.HopDurationSeconds)
        options.HopDurationSeconds = 0.050;
    end

    if ~isfield(options, "IncludeLFEInSpatial") || isempty(options.IncludeLFEInSpatial)
        options.IncludeLFEInSpatial = false;
    end

    if ~isfield(options, "EnergyFloorDBFS") || isempty(options.EnergyFloorDBFS)
        options.EnergyFloorDBFS = -120;
    end

    validatePositiveScalar(options.FrameDurationSeconds, "options.FrameDurationSeconds");
    validatePositiveScalar(options.HopDurationSeconds, "options.HopDurationSeconds");
    validateFiniteScalar(options.EnergyFloorDBFS, "options.EnergyFloorDBFS");

    options.IncludeLFEInSpatial = logical(options.IncludeLFEInSpatial);
end

function channelMapTable = createDefaultChannelMap(numChannels)

    FileChannel = (1:numChannels).';
    SpeakerLabel = "Ch" + string(FileChannel);
    Group = repmat("Unknown", numChannels, 1);
    IsLFE = false(numChannels, 1);
    IncludeInLoudness = true(numChannels, 1);
    IncludeInSpatial = true(numChannels, 1);
    LoudnessWeight = ones(numChannels, 1);
    AzimuthDeg = zeros(numChannels, 1);
    ElevationDeg = zeros(numChannels, 1);

    channelMapTable = table( ...
        FileChannel, ...
        SpeakerLabel, ...
        Group, ...
        IsLFE, ...
        IncludeInLoudness, ...
        IncludeInSpatial, ...
        LoudnessWeight, ...
        AzimuthDeg, ...
        ElevationDeg);
end

function channelMapTable = normalizeChannelMap(channelMapTable, numChannels)

    if ~istable(channelMapTable)
        error("computeSpatialEnergy:InvalidChannelMap", ...
            "channelMapTable must be a MATLAB table.");
    end

    if height(channelMapTable) ~= numChannels
        error("computeSpatialEnergy:InvalidChannelMap", ...
            "channelMapTable must have one row per audio channel.");
    end

    names = string(channelMapTable.Properties.VariableNames);

    if ~ismember("FileChannel", names)
        channelMapTable.FileChannel = (1:numChannels).';
    end

    if ~ismember("SpeakerLabel", names)
        channelMapTable.SpeakerLabel = "Ch" + string((1:numChannels).');
    end

    if ~ismember("Group", names)
        channelMapTable.Group = repmat("Unknown", numChannels, 1);
    end

    if ~ismember("IsLFE", names)
        channelMapTable.IsLFE = false(numChannels, 1);
    end

    if ~ismember("IncludeInLoudness", names)
        channelMapTable.IncludeInLoudness = true(numChannels, 1);
    end

    if ~ismember("IncludeInSpatial", names)
        channelMapTable.IncludeInSpatial = true(numChannels, 1);
    end

    if ~ismember("LoudnessWeight", names)
        channelMapTable.LoudnessWeight = ones(numChannels, 1);
    end

    if ~ismember("AzimuthDeg", names)
        channelMapTable.AzimuthDeg = zeros(numChannels, 1);
    end

    if ~ismember("ElevationDeg", names)
        channelMapTable.ElevationDeg = zeros(numChannels, 1);
    end

    channelMapTable.FileChannel = double(channelMapTable.FileChannel(:));
    channelMapTable.SpeakerLabel = string(channelMapTable.SpeakerLabel(:));
    channelMapTable.Group = string(channelMapTable.Group(:));
    channelMapTable.IsLFE = convertToLogical(channelMapTable.IsLFE);
    channelMapTable.IncludeInLoudness = convertToLogical(channelMapTable.IncludeInLoudness);
    channelMapTable.IncludeInSpatial = convertToLogical(channelMapTable.IncludeInSpatial);
    channelMapTable.LoudnessWeight = double(channelMapTable.LoudnessWeight(:));
    channelMapTable.AzimuthDeg = double(channelMapTable.AzimuthDeg(:));
    channelMapTable.ElevationDeg = double(channelMapTable.ElevationDeg(:));

    if any(~isfinite(channelMapTable.FileChannel)) || ...
            any(channelMapTable.FileChannel < 1) || ...
            any(channelMapTable.FileChannel > numChannels) || ...
            any(mod(channelMapTable.FileChannel, 1) ~= 0)
        error("computeSpatialEnergy:InvalidChannelMap", ...
            "FileChannel values must be valid channel numbers.");
    end
end

function groupTable = buildGroupSummaryTable(channelTable)

    groups = unique(string(channelTable.Group));
    groups(groups == "") = [];

    Group = strings(0, 1);
    ChannelCount = zeros(0, 1);
    Channels = strings(0, 1);
    MeanEnergy = zeros(0, 1);
    MeanEnergyDBFS = zeros(0, 1);
    EnergyPercent = zeros(0, 1);

    totalEnergy = sum(channelTable.MeanEnergy) + eps;

    for k = 1:numel(groups)
        currentGroup = groups(k);
        mask = string(channelTable.Group) == currentGroup;

        if ~any(mask)
            continue;
        end

        groupEnergy = sum(channelTable.MeanEnergy(mask));

        Group(end + 1, 1) = currentGroup; %#ok<AGROW>
        ChannelCount(end + 1, 1) = sum(mask); %#ok<AGROW>
        Channels(end + 1, 1) = strjoin(string(channelTable.SpeakerLabel(mask)).', ", "); %#ok<AGROW>
        MeanEnergy(end + 1, 1) = groupEnergy; %#ok<AGROW>
        MeanEnergyDBFS(end + 1, 1) = 10 * log10(groupEnergy + eps); %#ok<AGROW>
        EnergyPercent(end + 1, 1) = 100 * groupEnergy / totalEnergy; %#ok<AGROW>
    end

    groupTable = table( ...
        Group, ...
        ChannelCount, ...
        Channels, ...
        MeanEnergy, ...
        MeanEnergyDBFS, ...
        EnergyPercent);
end

function logicalVector = convertToLogical(inputVector)

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

function validatePositiveScalar(value, name)

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error("computeSpatialEnergy:InvalidOptions", ...
            "%s must be a positive scalar.", name);
    end
end

function validateFiniteScalar(value, name)

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error("computeSpatialEnergy:InvalidOptions", ...
            "%s must be a finite scalar.", name);
    end
end