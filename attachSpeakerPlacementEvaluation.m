function roomModel = attachSpeakerPlacementEvaluation(roomModel, formatName, standardName)
%ATTACHSPEAKERPLACEMENTEVALUATION Safe compatibility wrapper.
%
% defaultRoomModel already calculates placement status and notes.
% This function only preserves/refreshes metadata and avoids breaking
% the room model.

    if nargin < 2
        formatName = "unknown";
    end

    if nargin < 3
        standardName = "Dolby-style Orthogonal Mix Room";
    end

    if isempty(roomModel) || ~isstruct(roomModel)
        return;
    end

    roomModel.FormatName = string(formatName);
    roomModel.PlacementStandardName = string(standardName);

    if ~isfield(roomModel, "Validation") || ~isstruct(roomModel.Validation)
        roomModel.Validation = struct();
    end

    roomModel.Validation.PlacementStandardName = string(standardName);

    if ~isfield(roomModel, "SpeakerTable") || ~istable(roomModel.SpeakerTable)
        return;
    end

    speakerTable = roomModel.SpeakerTable;
    n = height(speakerTable);

    names = string(speakerTable.Properties.VariableNames);

    Speaker = getStringColumn(speakerTable, "SpeakerLabel", "Spk" + string((1:n).'));
    Group = getStringColumn(speakerTable, "Group", repmat("Unknown", n, 1));
    Distance_m = getNumericColumn(speakerTable, "DistanceMeters", NaN(n, 1));
    X_m = getNumericColumn(speakerTable, "X", NaN(n, 1));
    Y_m = getNumericColumn(speakerTable, "Y", NaN(n, 1));
    Z_m = getNumericColumn(speakerTable, "Z", NaN(n, 1));

    if ismember("WithinRoom", names)
        WithinRoom = convertToLogical(speakerTable.WithinRoom);
    else
        WithinRoom = true(n, 1);
    end

    if ismember("ActualAzimuthDeg", names)
        Azimuth_deg = double(speakerTable.ActualAzimuthDeg(:));
    elseif ismember("AzimuthDeg", names)
        Azimuth_deg = double(speakerTable.AzimuthDeg(:));
    else
        Azimuth_deg = NaN(n, 1);
    end

    if ismember("ActualElevationDeg", names)
        Elevation_deg = double(speakerTable.ActualElevationDeg(:));
    elseif ismember("ElevationDeg", names)
        Elevation_deg = double(speakerTable.ElevationDeg(:));
    else
        Elevation_deg = NaN(n, 1);
    end

    PlacementStatus = getStringColumn(speakerTable, "PlacementStatus", repmat("Unchecked", n, 1));
    PlacementNote = getStringColumn(speakerTable, "PlacementNote", repmat("", n, 1));

    roomModel.PlacementTable = table( ...
        Speaker, ...
        Group, ...
        roundFinite(Distance_m, 2), ...
        roundFinite(X_m, 2), ...
        roundFinite(Y_m, 2), ...
        roundFinite(Z_m, 2), ...
        WithinRoom, ...
        roundFinite(Azimuth_deg, 1), ...
        roundFinite(Elevation_deg, 1), ...
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
end

function values = getStringColumn(tbl, columnName, defaultValues)

    names = string(tbl.Properties.VariableNames);
    columnName = string(columnName);

    if ismember(columnName, names)
        values = string(tbl.(char(columnName))(:));
    else
        values = string(defaultValues(:));
    end
end

function values = getNumericColumn(tbl, columnName, defaultValues)

    names = string(tbl.Properties.VariableNames);
    columnName = string(columnName);

    if ismember(columnName, names)
        values = double(tbl.(char(columnName))(:));
    else
        values = double(defaultValues(:));
    end
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

function roundedValues = roundFinite(values, decimalPlaces)

    roundedValues = values;
    finiteMask = isfinite(values);

    scaleFactor = 10 ^ decimalPlaces;
    roundedValues(finiteMask) = round(values(finiteMask) * scaleFactor) ./ scaleFactor;
end