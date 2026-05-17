function roomOptions = buildRoomSetupOptions(roomDimensionsMeters, setupConfig)
%BUILDROOMSETUPOPTIONS Build room setup options for defaultRoomModel().
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Centralize room setup behavior so the app can support:
%       1. Dolby/ITU reference-style default room setup
%       2. Optional manual listener-position override
%       3. Optional manual measured speaker-distance override
%
% This function does NOT:
%   - move speakers directly
%   - analyze audio
%   - plot anything
%
% It only creates the options struct passed into defaultRoomModel().
%
% Inputs:
%   roomDimensionsMeters - [length width height] in meters
%
%   setupConfig          - optional struct with fields:
%       RoomSetupMode
%       PlacementStandardName
%       UseManualListenerPosition
%       ManualListenerPositionMeters
%       UseMeasuredSpeakerDistances
%       ManualSpeakerDistancesMeters
%       ListenerDepthRatio
%       ListenerEarHeightMeters
%       PreserveFrontArc
%       AutoDistanceScale
%       MinimumAutoSpeakerDistanceMeters
%       SpeedOfSoundMetersPerSecond
%       TemperatureC
%       WallAbsorption
%       WallScattering
%
% Output:
%   roomOptions - options struct for defaultRoomModel()

    %% Validate room dimensions

    if nargin < 1 || isempty(roomDimensionsMeters)
        roomDimensionsMeters = [6.0, 4.5, 2.7];
    end

    if ~isnumeric(roomDimensionsMeters) || ...
            numel(roomDimensionsMeters) ~= 3 || ...
            any(~isfinite(roomDimensionsMeters)) || ...
            any(roomDimensionsMeters <= 0)
        error("buildRoomSetupOptions:InvalidRoomDimensions", ...
            "roomDimensionsMeters must be [length width height] with positive finite values.");
    end

    roomDimensionsMeters = double(roomDimensionsMeters(:).');

    %% Defaults

    if nargin < 2 || isempty(setupConfig)
        setupConfig = struct();
    end

    if ~isstruct(setupConfig)
        error("buildRoomSetupOptions:InvalidSetupConfig", ...
            "setupConfig must be a struct.");
    end

    setupConfig = applySetupDefaults(setupConfig, roomDimensionsMeters);

    %% Build room options

    roomOptions = struct();

    % Core room geometry
    roomOptions.RoomDimensionsMeters = roomDimensionsMeters;

    % Standards / layout identity
    roomOptions.RoomSetupMode = string(setupConfig.RoomSetupMode);
    roomOptions.PlacementStandardName = string(setupConfig.PlacementStandardName);

    % Default behavior:
    % Dolby/ITU reference-style layout generated from room dimensions.
    roomOptions.UseIdealListenerPosition = ~logical(setupConfig.UseManualListenerPosition);
    roomOptions.ListenerDepthRatio = setupConfig.ListenerDepthRatio;
    roomOptions.ListenerEarHeightMeters = setupConfig.ListenerEarHeightMeters;
    roomOptions.PreserveFrontArc = logical(setupConfig.PreserveFrontArc);

    % Advanced manual listener override
    if setupConfig.UseManualListenerPosition
        roomOptions.ListenerPositionMeters = setupConfig.ManualListenerPositionMeters;
    else
        roomOptions.ListenerPositionMeters = computeDefaultListenerPosition( ...
            roomDimensionsMeters, ...
            setupConfig.ListenerDepthRatio, ...
            setupConfig.ListenerEarHeightMeters);
    end

    % Speaker distance mode
    if setupConfig.UseMeasuredSpeakerDistances
        roomOptions.SpeakerDistanceMode = "ManualDistances";
        roomOptions.ManualSpeakerDistancesMeters = setupConfig.ManualSpeakerDistancesMeters;
    else
        roomOptions.SpeakerDistanceMode = "AutoIdeal";
        roomOptions.ManualSpeakerDistancesMeters = [];
    end

    % Auto layout tuning
    roomOptions.AutoDistanceScale = setupConfig.AutoDistanceScale;
    roomOptions.MinimumAutoSpeakerDistanceMeters = setupConfig.MinimumAutoSpeakerDistanceMeters;

    % Physical / acoustic constants
    roomOptions.SpeedOfSoundMetersPerSecond = setupConfig.SpeedOfSoundMetersPerSecond;
    roomOptions.TemperatureC = setupConfig.TemperatureC;
    roomOptions.WallAbsorption = setupConfig.WallAbsorption;
    roomOptions.WallScattering = setupConfig.WallScattering;

    % Store advanced override flags for app display/debugging
    roomOptions.UseManualListenerPosition = logical(setupConfig.UseManualListenerPosition);
    roomOptions.UseMeasuredSpeakerDistances = logical(setupConfig.UseMeasuredSpeakerDistances);
end

%% Defaults

function setupConfig = applySetupDefaults(setupConfig, roomDimensionsMeters)

    if ~isfield(setupConfig, "RoomSetupMode") || isempty(setupConfig.RoomSetupMode)
        setupConfig.RoomSetupMode = "DolbyReference";
    end

    if ~isfield(setupConfig, "PlacementStandardName") || isempty(setupConfig.PlacementStandardName)
        setupConfig.PlacementStandardName = "DolbyITU";
    end

    if ~isfield(setupConfig, "UseManualListenerPosition") || isempty(setupConfig.UseManualListenerPosition)
        setupConfig.UseManualListenerPosition = false;
    end

    if ~isfield(setupConfig, "ManualListenerPositionMeters") || isempty(setupConfig.ManualListenerPositionMeters)
        setupConfig.ManualListenerPositionMeters = computeDefaultListenerPosition( ...
            roomDimensionsMeters, ...
            0.38, ...
            1.20);
    end

    if ~isfield(setupConfig, "UseMeasuredSpeakerDistances") || isempty(setupConfig.UseMeasuredSpeakerDistances)
        setupConfig.UseMeasuredSpeakerDistances = false;
    end

    if ~isfield(setupConfig, "ManualSpeakerDistancesMeters")
        setupConfig.ManualSpeakerDistancesMeters = [];
    end

    if ~isfield(setupConfig, "ListenerDepthRatio") || isempty(setupConfig.ListenerDepthRatio)
        setupConfig.ListenerDepthRatio = 0.38;
    end

    if ~isfield(setupConfig, "ListenerEarHeightMeters") || isempty(setupConfig.ListenerEarHeightMeters)
        setupConfig.ListenerEarHeightMeters = 1.20;
    end

    if ~isfield(setupConfig, "PreserveFrontArc") || isempty(setupConfig.PreserveFrontArc)
        setupConfig.PreserveFrontArc = true;
    end

    if ~isfield(setupConfig, "AutoDistanceScale") || isempty(setupConfig.AutoDistanceScale)
        setupConfig.AutoDistanceScale = 0.85;
    end

    if ~isfield(setupConfig, "MinimumAutoSpeakerDistanceMeters") || isempty(setupConfig.MinimumAutoSpeakerDistanceMeters)
        setupConfig.MinimumAutoSpeakerDistanceMeters = 0.75;
    end

    if ~isfield(setupConfig, "SpeedOfSoundMetersPerSecond") || isempty(setupConfig.SpeedOfSoundMetersPerSecond)
        setupConfig.SpeedOfSoundMetersPerSecond = 343;
    end

    if ~isfield(setupConfig, "TemperatureC") || isempty(setupConfig.TemperatureC)
        setupConfig.TemperatureC = 20;
    end

    if ~isfield(setupConfig, "WallAbsorption") || isempty(setupConfig.WallAbsorption)
        setupConfig.WallAbsorption = 0.30;
    end

    if ~isfield(setupConfig, "WallScattering") || isempty(setupConfig.WallScattering)
        setupConfig.WallScattering = 0.05;
    end

    %% Validate scalar fields

    validateRange01(setupConfig.ListenerDepthRatio, "ListenerDepthRatio");
    validatePositiveScalar(setupConfig.ListenerEarHeightMeters, "ListenerEarHeightMeters");
    validatePositiveScalar(setupConfig.AutoDistanceScale, "AutoDistanceScale");
    validatePositiveScalar(setupConfig.MinimumAutoSpeakerDistanceMeters, "MinimumAutoSpeakerDistanceMeters");
    validatePositiveScalar(setupConfig.SpeedOfSoundMetersPerSecond, "SpeedOfSoundMetersPerSecond");
    validateFiniteScalar(setupConfig.TemperatureC, "TemperatureC");
    validateRange01(setupConfig.WallAbsorption, "WallAbsorption");
    validateRange01(setupConfig.WallScattering, "WallScattering");

    if setupConfig.AutoDistanceScale > 1
        error("buildRoomSetupOptions:InvalidAutoDistanceScale", ...
            "AutoDistanceScale must be greater than 0 and less than or equal to 1.");
    end

    %% Validate manual listener position

    if setupConfig.UseManualListenerPosition
        validateVector3( ...
            setupConfig.ManualListenerPositionMeters, ...
            "ManualListenerPositionMeters");

        setupConfig.ManualListenerPositionMeters = ...
            double(setupConfig.ManualListenerPositionMeters(:).');
    end

    %% Validate manual measured speaker distances

    if setupConfig.UseMeasuredSpeakerDistances
        if isempty(setupConfig.ManualSpeakerDistancesMeters)
            error("buildRoomSetupOptions:MissingManualSpeakerDistances", ...
                "ManualSpeakerDistancesMeters is required when UseMeasuredSpeakerDistances is true.");
        end

        if ~isnumeric(setupConfig.ManualSpeakerDistancesMeters) || ...
                any(~isfinite(setupConfig.ManualSpeakerDistancesMeters)) || ...
                any(setupConfig.ManualSpeakerDistancesMeters <= 0)
            error("buildRoomSetupOptions:InvalidManualSpeakerDistances", ...
                "ManualSpeakerDistancesMeters must contain positive finite values.");
        end

        setupConfig.ManualSpeakerDistancesMeters = ...
            double(setupConfig.ManualSpeakerDistancesMeters(:));
    end

    setupConfig.RoomSetupMode = string(setupConfig.RoomSetupMode);
    setupConfig.PlacementStandardName = string(setupConfig.PlacementStandardName);
    setupConfig.UseManualListenerPosition = logical(setupConfig.UseManualListenerPosition);
    setupConfig.UseMeasuredSpeakerDistances = logical(setupConfig.UseMeasuredSpeakerDistances);
    setupConfig.PreserveFrontArc = logical(setupConfig.PreserveFrontArc);
end

%% Listener helper

function listenerPosition = computeDefaultListenerPosition(roomDimensionsMeters, depthRatio, earHeightMeters)

    roomLength = roomDimensionsMeters(1);
    roomWidth = roomDimensionsMeters(2);
    roomHeight = roomDimensionsMeters(3);

    margin = 0.10;

    x = roomWidth / 2;
    y = roomLength * depthRatio;
    z = min(earHeightMeters, roomHeight - margin);

    x = clampValue(x, margin, roomWidth - margin);
    y = clampValue(y, margin, roomLength - margin);
    z = clampValue(z, margin, roomHeight - margin);

    listenerPosition = [x, y, z];
end

function value = clampValue(value, minValue, maxValue)

    value = max(minValue, min(maxValue, value));
end

%% Validation helpers

function validateVector3(value, name)

    if ~isnumeric(value) || numel(value) ~= 3 || any(~isfinite(value))
        error("buildRoomSetupOptions:InvalidVector3", ...
            "%s must be a numeric vector with three finite values.", name);
    end
end

function validatePositiveScalar(value, name)

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error("buildRoomSetupOptions:InvalidPositiveScalar", ...
            "%s must be a positive scalar.", name);
    end
end

function validateFiniteScalar(value, name)

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error("buildRoomSetupOptions:InvalidFiniteScalar", ...
            "%s must be a finite scalar.", name);
    end
end

function validateRange01(value, name)

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 0 || value > 1
        error("buildRoomSetupOptions:InvalidRange01", ...
            "%s must be between 0 and 1.", name);
    end
end