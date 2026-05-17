function roomModel = defaultRoomModel(channelMapTable, roomOptions)
%DEFAULTROOMMODEL Dolby-style spec-first room model.
%
% Project:
%   Immersive Metering Tool
%
% Coordinate convention:
%   X = room width, left to right, meters
%   Y = room length, front/screen to rear, meters
%   Z = height, meters
%
% Critical left/right convention:
%   Smaller X = listener's left side
%   Larger X  = listener's right side
%
% Angular convention:
%   0 deg       = front/screen
%   negative az = left
%   positive az = right
%
% Design behavior:
%   This file prioritizes Dolby-style target azimuth/elevation placement.
%   It does not force a purely wall-based or purely arc-based layout.
%   It places each speaker along its target angle at a practical distance
%   that fits inside the room.

    %% Validate input

    if nargin < 1 || isempty(channelMapTable) || ~istable(channelMapTable)
        error("defaultRoomModel:InvalidChannelMap", ...
            "channelMapTable must be a nonempty MATLAB table.");
    end

    if nargin < 2 || isempty(roomOptions) || ~isstruct(roomOptions)
        roomOptions = struct();
    end

    channelMapTable = normalizeChannelMapTable(channelMapTable);

    %% Room dimensions

    roomDimensions = getOption(roomOptions, "RoomDimensionsMeters", [6.0 4.5 2.7]);
    roomDimensions = double(roomDimensions(:).');

    if numel(roomDimensions) ~= 3 || any(~isfinite(roomDimensions)) || any(roomDimensions <= 0)
        roomDimensions = [6.0 4.5 2.7];
    end

    roomLength = roomDimensions(1);
    roomWidth  = roomDimensions(2);
    roomHeight = roomDimensions(3);

    margins = getRoomMargins(roomDimensions);

    %% Acoustic constants

    speedOfSound = double(getOption(roomOptions, "SpeedOfSoundMetersPerSecond", 343));

    if ~isfinite(speedOfSound) || speedOfSound <= 0
        speedOfSound = 343;
    end

    earHeight = double(getOption(roomOptions, "ListenerEarHeightMeters", 1.20));

    if ~isfinite(earHeight) || earHeight <= 0
        earHeight = 1.20;
    end

    earHeight = clamp(earHeight, 0.20, roomHeight);

    %% Listener position

    useManualListener = logical(getOption(roomOptions, "UseManualListenerPosition", false));

    if useManualListener
        listener = double(getOption(roomOptions, "ListenerPositionMeters", ...
            [roomWidth / 2, roomLength * 0.60, earHeight]));

        listener = listener(:).';

        if numel(listener) ~= 3 || any(~isfinite(listener))
            listener = [roomWidth / 2, roomLength * 0.60, earHeight];
        end
    else
        listenerDepthRatio = double(getOption(roomOptions, "ListenerDepthRatio", 0.60));

        if ~isfinite(listenerDepthRatio)
            listenerDepthRatio = 0.60;
        end

        % Dolby mix-room references commonly place the mix position in the
        % middle-to-rear portion of the speaker layout. Keep the default
        % in a practical 0.50 to 0.70 range.
        listenerDepthRatio = clamp(listenerDepthRatio, 0.50, 0.70);

        listener = [roomWidth / 2, roomLength * listenerDepthRatio, earHeight];
    end

    listener(1) = clamp(listener(1), margins.Left,  roomWidth  - margins.Right);
    listener(2) = clamp(listener(2), margins.Front, roomLength - margins.Rear);
    listener(3) = clamp(listener(3), 0.20, roomHeight);

    %% Manual speaker-distance options

    speakerDistanceMode = string(getOption(roomOptions, "SpeakerDistanceMode", "DolbyReference"));
    manualDistances = double(getOption(roomOptions, "ManualSpeakerDistancesMeters", []));

    numSpeakers = height(channelMapTable);

    if numel(manualDistances) ~= numSpeakers
        manualDistances = NaN(numSpeakers, 1);
    else
        manualDistances = manualDistances(:);
    end

    %% Build specs

    speakerSpecs = repmat(emptySpeakerSpec(), numSpeakers, 1);

    for k = 1:numSpeakers
        speakerSpecs(k) = getDolbyStyleSpeakerSpec( ...
            string(channelMapTable.SpeakerLabel(k)), ...
            string(channelMapTable.Group(k)), ...
            logical(channelMapTable.IsLFE(k)));
    end

    %% Allocate output arrays

    X = NaN(numSpeakers, 1);
    Y = NaN(numSpeakers, 1);
    Z = NaN(numSpeakers, 1);

    TargetAzimuthDeg = NaN(numSpeakers, 1);
    TargetElevationDeg = NaN(numSpeakers, 1);

    AzimuthRangeMinDeg = NaN(numSpeakers, 1);
    AzimuthRangeMaxDeg = NaN(numSpeakers, 1);
    ElevationRangeMinDeg = NaN(numSpeakers, 1);
    ElevationRangeMaxDeg = NaN(numSpeakers, 1);

    DistanceSource = repmat("GeneratedSpecTarget", numSpeakers, 1);
    PlacementStatus = repmat("Unchecked", numSpeakers, 1);
    PlacementNote = strings(numSpeakers, 1);

    %% Position speakers

    for k = 1:numSpeakers
        label = string(channelMapTable.SpeakerLabel(k));
        group = string(channelMapTable.Group(k));
        isLFE = logical(channelMapTable.IsLFE(k));
        spec = speakerSpecs(k);

        TargetAzimuthDeg(k) = spec.TargetAzimuthDeg;
        TargetElevationDeg(k) = spec.TargetElevationDeg;

        AzimuthRangeMinDeg(k) = spec.AzimuthRangeMinDeg;
        AzimuthRangeMaxDeg(k) = spec.AzimuthRangeMaxDeg;
        ElevationRangeMinDeg(k) = spec.ElevationRangeMinDeg;
        ElevationRangeMaxDeg(k) = spec.ElevationRangeMaxDeg;

        if speakerDistanceMode == "ManualDistances" && ...
                isfinite(manualDistances(k)) && manualDistances(k) > 0 && ...
                isfinite(spec.TargetAzimuthDeg)

            [X(k), Y(k), Z(k)] = positionFromAzElDistance( ...
                listener, ...
                spec.TargetAzimuthDeg, ...
                spec.TargetElevationDeg, ...
                manualDistances(k));

            DistanceSource(k) = "ManualDistance";
        else
            [X(k), Y(k), Z(k), DistanceSource(k)] = positionSpeakerToSpecTarget( ...
                label, ...
                group, ...
                isLFE, ...
                spec, ...
                listener, ...
                roomDimensions, ...
                margins);
        end

        X(k) = clamp(X(k), 0, roomWidth);
        Y(k) = clamp(Y(k), 0, roomLength);
        Z(k) = clamp(Z(k), 0, roomHeight);
    end

    %% Geometry and delays

    dx = X - listener(1);
    dy = Y - listener(2);
    dz = Z - listener(3);

    DistanceMeters = sqrt(dx.^2 + dy.^2 + dz.^2);
    DelayMilliseconds = DistanceMeters ./ speedOfSound .* 1000;

    horizontalDistance = sqrt(dx.^2 + dy.^2);

    ActualAzimuthDeg = atan2d(-dx, -dy);
    ActualElevationDeg = atan2d(dz, horizontalDistance);

    validDistance = isfinite(DistanceMeters) & DistanceMeters > 0;

    ReferenceSpeaker = false(numSpeakers, 1);
    DelayToAddMilliseconds = NaN(numSpeakers, 1);

    if any(validDistance)
        referenceDistance = max(DistanceMeters(validDistance));

        ReferenceSpeaker = ...
            abs(DistanceMeters - referenceDistance) <= max(1e-9, referenceDistance * 1e-9);

        DelayToAddMilliseconds(validDistance) = ...
            (referenceDistance - DistanceMeters(validDistance)) ./ speedOfSound .* 1000;
    end

    WithinRoom = ...
        X >= 0 & X <= roomWidth & ...
        Y >= 0 & Y <= roomLength & ...
        Z >= 0 & Z <= roomHeight;

    %% Placement evaluation

    for k = 1:numSpeakers
        [PlacementStatus(k), PlacementNote(k)] = evaluatePlacement( ...
            string(channelMapTable.SpeakerLabel(k)), ...
            ActualAzimuthDeg(k), ...
            ActualElevationDeg(k), ...
            TargetAzimuthDeg(k), ...
            TargetElevationDeg(k), ...
            AzimuthRangeMinDeg(k), ...
            AzimuthRangeMaxDeg(k), ...
            ElevationRangeMinDeg(k), ...
            ElevationRangeMaxDeg(k), ...
            WithinRoom(k), ...
            DistanceSource(k));
    end

    %% Build SpeakerTable

    SpeakerTable = channelMapTable;

    SpeakerTable.X = X;
    SpeakerTable.Y = Y;
    SpeakerTable.Z = Z;

    SpeakerTable.DistanceMeters = DistanceMeters;
    SpeakerTable.DisplayDistanceMeters = DistanceMeters;

    SpeakerTable.DelayMilliseconds = DelayMilliseconds;
    SpeakerTable.DelayToAddMilliseconds = DelayToAddMilliseconds;
    SpeakerTable.ReferenceSpeaker = ReferenceSpeaker;

    SpeakerTable.TargetAzimuthDeg = TargetAzimuthDeg;
    SpeakerTable.TargetElevationDeg = TargetElevationDeg;

    SpeakerTable.ActualAzimuthDeg = ActualAzimuthDeg;
    SpeakerTable.ActualElevationDeg = ActualElevationDeg;

    SpeakerTable.AzimuthDeg = ActualAzimuthDeg;
    SpeakerTable.ElevationDeg = ActualElevationDeg;

    SpeakerTable.AzimuthRangeMinDeg = AzimuthRangeMinDeg;
    SpeakerTable.AzimuthRangeMaxDeg = AzimuthRangeMaxDeg;

    SpeakerTable.ElevationRangeMinDeg = ElevationRangeMinDeg;
    SpeakerTable.ElevationRangeMaxDeg = ElevationRangeMaxDeg;

    SpeakerTable.DistanceSource = DistanceSource;
    SpeakerTable.WithinRoom = WithinRoom;
    SpeakerTable.PlacementStatus = PlacementStatus;
    SpeakerTable.PlacementNote = PlacementNote;

    %% Build PlacementTable

    PlacementTable = table( ...
        string(SpeakerTable.SpeakerLabel), ...
        string(SpeakerTable.Group), ...
        DistanceMeters, ...
        X, ...
        Y, ...
        Z, ...
        WithinRoom, ...
        ActualAzimuthDeg, ...
        ActualElevationDeg, ...
        PlacementStatus, ...
        PlacementNote, ...
        'VariableNames', { ...
            'Speaker', ...
            'Group', ...
            'Distance_m', ...
            'X_m', ...
            'Y_m', ...
            'Z_m', ...
            'WithinRoom', ...
            'Azimuth_deg', ...
            'Elevation_deg', ...
            'PlacementStatus', ...
            'PlacementNote'});

    %% Validation

    validation = struct();

    validation.SpeakersInBounds = all(WithinRoom);
    validation.SpeedOfSoundMetersPerSecond = speedOfSound;
    validation.RoomSetupMode = "DolbyStyleSpecTarget";
    validation.PlacementStandardName = "Dolby-style Spec Target Layout";

    if any(ReferenceSpeaker)
        validation.DelayReferenceSpeakerLabel = ...
            strjoin(string(SpeakerTable.SpeakerLabel(ReferenceSpeaker)).', ", ");
    else
        validation.DelayReferenceSpeakerLabel = "None";
    end

    validation.MaxDelayToAddMilliseconds = maxFinite(DelayToAddMilliseconds);
    validation.MaxDelayMilliseconds = maxFinite(DelayMilliseconds);

    if all(PlacementStatus == "In Spec" | PlacementStatus == "OK")
        validation.PlacementStatus = "In Spec";
    elseif any(PlacementStatus == "Out of Room")
        validation.PlacementStatus = "Review - Out of Room";
    else
        validation.PlacementStatus = "Review";
    end

    reviewMask = ~(PlacementStatus == "In Spec" | PlacementStatus == "OK");

    if any(reviewMask)
        validation.ReviewSpeakerLabels = strjoin(string(SpeakerTable.SpeakerLabel(reviewMask)).', ", ");
    else
        validation.ReviewSpeakerLabels = "";
    end

    %% Final room model

    roomModel = struct();

    roomModel.RoomDimensionsMeters = roomDimensions;
    roomModel.ListenerPositionMeters = listener;
    roomModel.SpeedOfSoundMetersPerSecond = speedOfSound;

    roomModel.RoomSetupMode = "DolbyStyleSpecTarget";
    roomModel.PlacementStandardName = "Dolby-style Spec Target Layout";
    roomModel.FormatName = inferFormatName(SpeakerTable);

    roomModel.SpeakerTable = SpeakerTable;
    roomModel.PlacementTable = PlacementTable;
    roomModel.Validation = validation;
end

%% ========================================================================
% Input normalization
% ========================================================================

function tbl = normalizeChannelMapTable(tbl)

    numRows = height(tbl);
    names = string(tbl.Properties.VariableNames);

    if ~ismember("FileChannel", names)
        tbl.FileChannel = (1:numRows).';
    end

    if ~ismember("SpeakerLabel", names)
        tbl.SpeakerLabel = "Ch" + string((1:numRows).');
    end

    if ~ismember("Group", names)
        tbl.Group = repmat("Unknown", numRows, 1);
    end

    if ~ismember("IsLFE", names)
        tbl.IsLFE = false(numRows, 1);
    end

    if ~ismember("IncludeInLoudness", names)
        tbl.IncludeInLoudness = ~convertToLogical(tbl.IsLFE);
    end

    if ~ismember("IncludeInSpatial", names)
        tbl.IncludeInSpatial = ~convertToLogical(tbl.IsLFE);
    end

    if ~ismember("LoudnessWeight", names)
        tbl.LoudnessWeight = ones(numRows, 1);
    end

    if ~ismember("AzimuthDeg", names)
        tbl.AzimuthDeg = zeros(numRows, 1);
    end

    if ~ismember("ElevationDeg", names)
        tbl.ElevationDeg = zeros(numRows, 1);
    end

    tbl.FileChannel = double(tbl.FileChannel(:));
    tbl.SpeakerLabel = string(tbl.SpeakerLabel(:));
    tbl.Group = string(tbl.Group(:));
    tbl.IsLFE = convertToLogical(tbl.IsLFE);
    tbl.IncludeInLoudness = convertToLogical(tbl.IncludeInLoudness);
    tbl.IncludeInSpatial = convertToLogical(tbl.IncludeInSpatial);
    tbl.LoudnessWeight = double(tbl.LoudnessWeight(:));
    tbl.AzimuthDeg = double(tbl.AzimuthDeg(:));
    tbl.ElevationDeg = double(tbl.ElevationDeg(:));
end

%% ========================================================================
% Dolby-style speaker target definitions
% ========================================================================

function spec = emptySpeakerSpec()

    spec = struct();

    spec.TargetAzimuthDeg = 0;
    spec.TargetElevationDeg = 0;

    spec.AzimuthRangeMinDeg = -180;
    spec.AzimuthRangeMaxDeg = 180;

    spec.ElevationRangeMinDeg = -20;
    spec.ElevationRangeMaxDeg = 20;

    spec.IsLFE = false;
    spec.IsHeight = false;
    spec.IsKnown = false;
end

function spec = getDolbyStyleSpeakerSpec(label, group, isLFE)

    key = normalizeSpeakerLabel(label);
    groupText = lower(string(group));

    spec = emptySpeakerSpec();

    if isLFE || key == "lfe" || contains(groupText, "lfe")
        spec.TargetAzimuthDeg = 0;
        spec.TargetElevationDeg = 0;
        spec.AzimuthRangeMinDeg = NaN;
        spec.AzimuthRangeMaxDeg = NaN;
        spec.ElevationRangeMinDeg = NaN;
        spec.ElevationRangeMaxDeg = NaN;
        spec.IsLFE = true;
        spec.IsKnown = true;
        return;
    end

    switch key
        case "l"
            spec.TargetAzimuthDeg = -30;
            spec.AzimuthRangeMinDeg = -40;
            spec.AzimuthRangeMaxDeg = -20;
            spec.IsKnown = true;

        case "r"
            spec.TargetAzimuthDeg = 30;
            spec.AzimuthRangeMinDeg = 20;
            spec.AzimuthRangeMaxDeg = 40;
            spec.IsKnown = true;

        case "c"
            spec.TargetAzimuthDeg = 0;
            spec.AzimuthRangeMinDeg = -10;
            spec.AzimuthRangeMaxDeg = 10;
            spec.IsKnown = true;

        case "ls"
            spec.TargetAzimuthDeg = -100;
            spec.AzimuthRangeMinDeg = -110;
            spec.AzimuthRangeMaxDeg = -90;
            spec.IsKnown = true;

        case "rs"
            spec.TargetAzimuthDeg = 100;
            spec.AzimuthRangeMinDeg = 90;
            spec.AzimuthRangeMaxDeg = 110;
            spec.IsKnown = true;

        case "lrs"
            spec.TargetAzimuthDeg = -135;
            spec.AzimuthRangeMinDeg = -160;
            spec.AzimuthRangeMaxDeg = -120;
            spec.IsKnown = true;

        case "rrs"
            spec.TargetAzimuthDeg = 135;
            spec.AzimuthRangeMinDeg = 120;
            spec.AzimuthRangeMaxDeg = 160;
            spec.IsKnown = true;

        case "ltm"
            spec.TargetAzimuthDeg = -90;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = -110;
            spec.AzimuthRangeMaxDeg = -70;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        case "rtm"
            spec.TargetAzimuthDeg = 90;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = 70;
            spec.AzimuthRangeMaxDeg = 110;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        case "ltf"
            spec.TargetAzimuthDeg = -30;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = -40;
            spec.AzimuthRangeMaxDeg = -20;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        case "rtf"
            spec.TargetAzimuthDeg = 30;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = 20;
            spec.AzimuthRangeMaxDeg = 40;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        case "ltr"
            spec.TargetAzimuthDeg = -135;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = -160;
            spec.AzimuthRangeMaxDeg = -120;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        case "rtr"
            spec.TargetAzimuthDeg = 135;
            spec.TargetElevationDeg = 45;
            spec.AzimuthRangeMinDeg = 120;
            spec.AzimuthRangeMaxDeg = 160;
            spec.ElevationRangeMinDeg = 30;
            spec.ElevationRangeMaxDeg = 55;
            spec.IsHeight = true;
            spec.IsKnown = true;

        otherwise
            spec.TargetAzimuthDeg = 0;
            spec.TargetElevationDeg = 0;
            spec.AzimuthRangeMinDeg = -180;
            spec.AzimuthRangeMaxDeg = 180;
            spec.ElevationRangeMinDeg = -90;
            spec.ElevationRangeMaxDeg = 90;
            spec.IsKnown = false;
    end
end

%% ========================================================================
% Speaker positioning
% ========================================================================

function margins = getRoomMargins(roomDimensions)

    roomLength = roomDimensions(1);
    roomWidth  = roomDimensions(2);
    roomHeight = roomDimensions(3);

    margins = struct();

    margins.Left   = max(0.25, roomWidth  * 0.05);
    margins.Right  = max(0.25, roomWidth  * 0.05);
    margins.Front  = max(0.25, roomLength * 0.05);
    margins.Rear   = max(0.25, roomLength * 0.05);
    margins.Ceiling = max(0.10, roomHeight * 0.04);
end

function [x, y, z, distanceSource] = positionSpeakerToSpecTarget( ...
    label, group, isLFE, spec, listener, roomDimensions, margins)

    roomLength = roomDimensions(1);
    roomWidth  = roomDimensions(2);
    roomHeight = roomDimensions(3);

    key = normalizeSpeakerLabel(label);
    groupText = lower(string(group));

    distanceSource = "GeneratedSpecTarget";

    if isLFE || spec.IsLFE || key == "lfe" || contains(groupText, "lfe")
        % Practical default subwoofer position.
        x = clamp(listener(1) + roomWidth * 0.18, margins.Left, roomWidth - margins.Right);
        y = margins.Front;
        z = min(0.35, roomHeight);
        distanceSource = "GeneratedLFE";
        return;
    end

    targetAz = spec.TargetAzimuthDeg;
    targetEl = spec.TargetElevationDeg;

    if ~isfinite(targetAz)
        targetAz = 0;
    end

    if ~isfinite(targetEl)
        targetEl = 0;
    end

    maxDistance = maxDistanceInsideRoomAlongAngle( ...
        listener, targetAz, targetEl, roomDimensions, margins);

    if ~isfinite(maxDistance) || maxDistance <= 0
        maxDistance = max(0.75, min(roomLength, roomWidth) * 0.35);
        distanceSource = "GeneratedFallback";
    end

    if spec.IsHeight
        % For height speakers, target elevation is the important part.
        % Use as much valid distance as needed to reach near-ceiling height,
        % while preserving target azimuth/elevation.
        desiredDistance = chooseHeightDistance(listener, targetEl, roomDimensions, margins);
        distanceMeters = min(desiredDistance, maxDistance * 0.96);
        distanceMeters = max(distanceMeters, 0.50);
        distanceSource = "GeneratedHeightTarget";
    else
        % For ear-level speakers, choose a strong practical radius that fits
        % the target angle. This may visually resemble an arc, but the
        % purpose is hitting target angles cleanly.
        desiredDistance = min(roomLength, roomWidth) * 0.48;
        desiredDistance = max(desiredDistance, 0.90);
        distanceMeters = min(desiredDistance, maxDistance * 0.96);
        distanceMeters = max(distanceMeters, 0.50);
        distanceSource = "GeneratedBedTarget";
    end

    [x, y, z] = positionFromAzElDistance(listener, targetAz, targetEl, distanceMeters);

    x = clamp(x, 0, roomWidth);
    y = clamp(y, 0, roomLength);
    z = clamp(z, 0, roomHeight);
end

function maxDistance = maxDistanceInsideRoomAlongAngle(listener, azimuthDeg, elevationDeg, roomDimensions, margins)

    roomLength = roomDimensions(1);
    roomWidth  = roomDimensions(2);
    roomHeight = roomDimensions(3);

    horizontalScale = cosd(elevationDeg);

    direction = [
       -horizontalScale * sind(azimuthDeg), ...
       -horizontalScale * cosd(azimuthDeg), ...
        sind(elevationDeg)
    ];

    minBounds = [
        margins.Left, ...
        margins.Front, ...
        0
    ];

    maxBounds = [
        roomWidth - margins.Right, ...
        roomLength - margins.Rear, ...
        roomHeight - margins.Ceiling
    ];

    maxDistance = Inf;

    for idx = 1:3
        d = direction(idx);
        p = listener(idx);

        if abs(d) < 1e-12
            continue;
        end

        if d > 0
            candidate = (maxBounds(idx) - p) / d;
        else
            candidate = (minBounds(idx) - p) / d;
        end

        if candidate > 0
            maxDistance = min(maxDistance, candidate);
        end
    end

    if ~isfinite(maxDistance)
        maxDistance = min(roomLength, roomWidth) * 0.35;
    end
end

function distanceMeters = chooseHeightDistance(listener, elevationDeg, roomDimensions, margins)

    roomHeight = roomDimensions(3);
    targetZ = roomHeight - margins.Ceiling;

    verticalRise = targetZ - listener(3);

    if verticalRise <= 0
        verticalRise = max(0.30, roomHeight * 0.20);
    end

    if abs(sind(elevationDeg)) < 1e-9
        distanceMeters = min(roomDimensions(1), roomDimensions(2)) * 0.35;
    else
        distanceMeters = verticalRise / sind(elevationDeg);
    end

    if ~isfinite(distanceMeters) || distanceMeters <= 0
        distanceMeters = min(roomDimensions(1), roomDimensions(2)) * 0.35;
    end
end

function [x, y, z] = positionFromAzElDistance(listener, azimuthDeg, elevationDeg, distanceMeters)

    horizontalDistance = distanceMeters * cosd(elevationDeg);

    % Listener-perspective coordinate convention:
    %   0 deg        = front/screen = smaller Y
    %   negative az  = listener left  = larger X
    %   positive az  = listener right = smaller X
    %
    % This makes:
    %   L  at -30 deg appear to the listener's left
    %   R  at +30 deg appear to the listener's right

    x = listener(1) - horizontalDistance * sind(azimuthDeg);
    y = listener(2) - horizontalDistance * cosd(azimuthDeg);
    z = listener(3) + distanceMeters * sind(elevationDeg);
end

%% ========================================================================
% Placement evaluation
% ========================================================================

function [status, note] = evaluatePlacement( ...
    label, actualAz, actualEl, targetAz, targetEl, ...
    azMin, azMax, elMin, elMax, withinRoom, distanceSource)

    label = string(label);

    if ~withinRoom
        status = "Out of Room";
        note = label + " is outside room bounds.";
        return;
    end

    azOK = true;
    elOK = true;

    if isfinite(azMin) && isfinite(azMax)
        azOK = actualAz >= azMin && actualAz <= azMax;
    end

    if isfinite(elMin) && isfinite(elMax)
        elOK = actualEl >= elMin && actualEl <= elMax;
    end

    if azOK && elOK
        status = "In Spec";
    else
        status = "Review";
    end

    if isfinite(targetAz) && isfinite(azMin) && isfinite(azMax)
        azText = sprintf( ...
            "Az target %.1f deg, acceptable %.1f to %.1f deg, actual %.1f deg.", ...
            targetAz, azMin, azMax, actualAz);
    elseif isfinite(targetAz)
        azText = sprintf( ...
            "Az target %.1f deg, actual %.1f deg.", ...
            targetAz, actualAz);
    else
        azText = sprintf("Az actual %.1f deg.", actualAz);
    end

    if isfinite(targetEl) && isfinite(elMin) && isfinite(elMax)
        elText = sprintf( ...
            "El target %.1f deg, acceptable %.1f to %.1f deg, actual %.1f deg.", ...
            targetEl, elMin, elMax, actualEl);
    elseif isfinite(targetEl)
        elText = sprintf( ...
            "El target %.1f deg, actual %.1f deg.", ...
            targetEl, actualEl);
    else
        elText = sprintf("El actual %.1f deg.", actualEl);
    end

    if azOK && elOK
        finalText = "Placement is within current Dolby-style target range.";
    elseif ~azOK && ~elOK
        finalText = "Review azimuth and elevation.";
    elseif ~azOK
        finalText = "Review azimuth.";
    else
        finalText = "Review elevation.";
    end

    note = string(azText) + " " + ...
           string(elText) + " " + ...
           "Source: " + string(distanceSource) + ". " + ...
           string(finalText);
end

%% ========================================================================
% Utilities
% ========================================================================

function value = getOption(options, name, defaultValue)

    fieldName = char(string(name));

    if isfield(options, fieldName)
        value = options.(fieldName);
    else
        value = defaultValue;
    end
end

function value = clamp(value, low, high)

    value = min(max(value, low), high);
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

function key = normalizeSpeakerLabel(label)

    key = lower(strtrim(string(label)));
    key = replace(key, " ", "");
    key = replace(key, "-", "");
    key = replace(key, "_", "");

    switch key
        case {"left"}
            key = "l";

        case {"right"}
            key = "r";

        case {"center", "centre"}
            key = "c";

        case {"sub", "subwoofer"}
            key = "lfe";

        case {"leftsurround", "lsurround"}
            key = "ls";

        case {"rightsurround", "rsurround"}
            key = "rs";

        case {"leftrear", "leftrearsurround", "leftrearsurrounds", "lr", "lrsurround"}
            key = "lrs";

        case {"rightrear", "rightrearsurround", "rightrearsurrounds", "rr", "rrsurround"}
            key = "rrs";

        case {"lefttopmiddle", "leftmiddleheight", "ltm"}
            key = "ltm";

        case {"righttopmiddle", "rightmiddleheight", "rtm"}
            key = "rtm";

        case {"lefttopfront", "leftfrontheight", "ltf"}
            key = "ltf";

        case {"righttopfront", "rightfrontheight", "rtf"}
            key = "rtf";

        case {"lefttoprear", "leftrearheight", "ltr"}
            key = "ltr";

        case {"righttoprear", "rightrearheight", "rtr"}
            key = "rtr";
    end
end

function value = maxFinite(values)

    values = values(:);
    values = values(isfinite(values));

    if isempty(values)
        value = NaN;
    else
        value = max(values);
    end
end

function formatName = inferFormatName(speakerTable)

    labels = lower(string(speakerTable.SpeakerLabel(:)));

    hasLFE = any(labels == "lfe");

    isHeight = ...
        contains(labels, "tf") | ...
        contains(labels, "tr") | ...
        contains(labels, "tm");

    bedCount = sum(~isHeight & labels ~= "lfe");
    heightCount = sum(isHeight);

    if hasLFE
        lfeText = ".1";
    else
        lfeText = ".0";
    end

    if heightCount > 0
        formatName = string(bedCount) + lfeText + "." + string(heightCount);
    else
        formatName = string(bedCount) + lfeText;
    end
end