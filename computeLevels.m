function [levelTable, levelData] = computeLevels(audioData, fs, channelLabels, options)
%COMPUTELEVELS Calculate basic per-channel level metrics for audio.
%
% This function is part of the Immersive Metering Tool project.
% It supports mono, stereo, 5.1, 7.1, 7.1.4, and custom channel counts.
%
% Inputs:
%   audioData      - Audio samples, size [numSamples x numChannels]
%   fs             - Sample rate in Hz
%   channelLabels  - Optional channel labels, string/cell/char
%   options        - Optional struct:
%                    options.ClipThreshold
%                    options.SilenceThresholdDBFS
%                    options.ReferenceLevel
%
% Outputs:
%   levelTable     - Table of per-channel level metrics
%   levelData      - Struct containing numeric arrays for each metric

    %% Input validation

    if nargin < 1 || isempty(audioData)
        error("computeLevels:InvalidAudioData", ...
            "audioData must be a nonempty numeric matrix.");
    end

    if ~isnumeric(audioData)
        error("computeLevels:InvalidAudioData", ...
            "audioData must be numeric.");
    end

    if ~isreal(audioData)
        error("computeLevels:InvalidAudioData", ...
            "audioData must contain real-valued audio samples.");
    end

    if any(~isfinite(audioData), "all")
        error("computeLevels:InvalidAudioData", ...
            "audioData must not contain NaN or Inf values.");
    end

    if nargin < 2 || isempty(fs)
        error("computeLevels:InvalidSampleRate", ...
            "fs must be provided as a positive scalar sample rate in Hz.");
    end

    if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error("computeLevels:InvalidSampleRate", ...
            "fs must be a positive scalar sample rate in Hz.");
    end

    % Convert row-vector mono audio to column-vector mono audio.
    if isvector(audioData)
        audioData = audioData(:);
    end

    if ndims(audioData) ~= 2
        error("computeLevels:InvalidAudioData", ...
            "audioData must be a 2-D matrix with size [numSamples x numChannels].");
    end

    [numSamples, numChannels] = size(audioData);

    if numSamples < 1 || numChannels < 1
        error("computeLevels:InvalidAudioData", ...
            "audioData must contain at least one sample and one channel.");
    end

    %% Channel labels

    if nargin < 3 || isempty(channelLabels)
        channelLabels = createDefaultChannelLabels(numChannels);
    else
        channelLabels = string(channelLabels);
        channelLabels = channelLabels(:);

        if numel(channelLabels) ~= numChannels
            error("computeLevels:InvalidChannelLabels", ...
                "channelLabels length must match the number of audio channels.");
        end
    end

    %% Options

    if nargin < 4 || isempty(options)
        options = struct();
    end

    if ~isstruct(options)
        error("computeLevels:InvalidOptions", ...
            "options must be a struct.");
    end

    if ~isfield(options, "ClipThreshold") || isempty(options.ClipThreshold)
        options.ClipThreshold = 0.999;
    end

    if ~isfield(options, "SilenceThresholdDBFS") || isempty(options.SilenceThresholdDBFS)
        options.SilenceThresholdDBFS = -60;
    end

    if ~isfield(options, "ReferenceLevel") || isempty(options.ReferenceLevel)
        options.ReferenceLevel = 1.0;
    end

    validateScalarPositive(options.ClipThreshold, "options.ClipThreshold");
    validateScalarFinite(options.SilenceThresholdDBFS, "options.SilenceThresholdDBFS");
    validateScalarPositive(options.ReferenceLevel, "options.ReferenceLevel");

    clipThreshold = options.ClipThreshold;
    silenceThresholdDBFS = options.SilenceThresholdDBFS;
    referenceLevel = options.ReferenceLevel;

    %% Metric calculations

    absAudio = abs(audioData);

    peakLinear = max(absAudio, [], 1);
    peakDBFS = 20 * log10((peakLinear ./ referenceLevel) + eps);

    rmsLinear = sqrt(mean(audioData.^2, 1));
    rmsDBFS = 20 * log10((rmsLinear ./ referenceLevel) + eps);

    crestFactorDB = peakDBFS - rmsDBFS;

    dcOffset = mean(audioData, 1);

    clipCount = sum(absAudio >= clipThreshold, 1);
    clipPercent = 100 * clipCount ./ numSamples;

    silenceThresholdLinear = referenceLevel * 10^(silenceThresholdDBFS / 20);
    silenceCount = sum(absAudio < silenceThresholdLinear, 1);
    silencePercent = 100 * silenceCount ./ numSamples;

    %% Build output struct

    levelData = struct();

    levelData.SampleRate = fs;
    levelData.NumSamples = numSamples;
    levelData.NumChannels = numChannels;
    levelData.ChannelLabels = channelLabels;

    levelData.PeakLinear = peakLinear(:);
    levelData.PeakDBFS = peakDBFS(:);
    levelData.RMSLinear = rmsLinear(:);
    levelData.RMSDBFS = rmsDBFS(:);
    levelData.CrestFactorDB = crestFactorDB(:);
    levelData.DCOffset = dcOffset(:);
    levelData.ClipCount = clipCount(:);
    levelData.ClipPercent = clipPercent(:);
    levelData.SilencePercent = silencePercent(:);

    levelData.Options = options;

    %% Build output table

    channelNumber = (1:numChannels).';

    levelTable = table( ...
        channelNumber, ...
        channelLabels, ...
        peakLinear(:), ...
        peakDBFS(:), ...
        rmsLinear(:), ...
        rmsDBFS(:), ...
        crestFactorDB(:), ...
        dcOffset(:), ...
        clipCount(:), ...
        clipPercent(:), ...
        silencePercent(:), ...
        'VariableNames', { ...
            'ChannelNumber', ...
            'ChannelLabel', ...
            'PeakLinear', ...
            'PeakDBFS', ...
            'RMSLinear', ...
            'RMSDBFS', ...
            'CrestFactorDB', ...
            'DCOffset', ...
            'ClipCount', ...
            'ClipPercent', ...
            'SilencePercent' ...
        } ...
    );

end

%% Local helper functions

function labels = createDefaultChannelLabels(numChannels)
%CREATEDEFAULTCHANNELLABELS Create basic labels when none are supplied.

    if numChannels == 1
        labels = "Mono";
    else
        labels = "Ch" + string(1:numChannels);
    end

    labels = labels(:);
end

function validateScalarPositive(value, name)
%VALIDATESCALARPOSITIVE Validate positive scalar numeric value.

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error("computeLevels:InvalidOption", ...
            "%s must be a positive scalar numeric value.", name);
    end
end

function validateScalarFinite(value, name)
%VALIDATESCALARFINITE Validate finite scalar numeric value.

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error("computeLevels:InvalidOption", ...
            "%s must be a finite scalar numeric value.", name);
    end
end