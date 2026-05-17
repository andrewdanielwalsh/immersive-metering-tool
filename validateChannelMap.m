
function [channelMapTable, validation] = validateChannelMap(numFileChannels, formatStruct, existingMap)
% validateChannelMap Build channel mapping table and validation info.
%
%   [channelMapTable, validation] = validateChannelMap(numFileChannels, formatStruct, existingMap)
%
% Inputs:
%   - numFileChannels : positive integer scalar number of channels detected in WAV.
%   - formatStruct    : format preset returned by getFormatMap(...) containing fields:
%                       Name, ChannelCount, ChannelNumbers, Labels, AzimuthDeg,
%                       ElevationDeg, Group, IsLFE, LoudnessWeight
%   - existingMap     : (optional) table with required columns (see below). If
%                       empty or not provided, a default map is created.
%
% Outputs:
%   - channelMapTable : table with columns:
%       FileChannel, SpeakerLabel, Group, IsLFE, IncludeInLoudness, IncludeInSpatial,
%       LoudnessWeight, AzimuthDeg, ElevationDeg, Status, Notes
%   - validation      : struct with fields:
%       IsValid, NumFileChannels, ExpectedFormatChannels, HasChannelCountMismatch,
%       HasUnmappedChannels, HasDuplicateSpeakerLabels, Warnings
%
% Notes:
%   - For normal channels IncludeInLoudness and IncludeInSpatial default to true.
%   - For LFE channels IncludeInLoudness and IncludeInSpatial default to false and
%     a default note is set.
%   - Extra file channels beyond the format are labeled "Unassigned_<n>" and marked
%     as ExtraFileChannel with IncludeInLoudness/Spatial = false and LoudnessWeight=0.

% -----------------------
% Input Validation
% -----------------------
validateattributes(numFileChannels, {'numeric'}, {'scalar','positive','integer','finite'}, mfilename, 'numFileChannels', 1);

% Basic formatStruct validation
requiredFields = ["Name","ChannelCount","ChannelNumbers","Labels","AzimuthDeg","ElevationDeg","Group","IsLFE","LoudnessWeight"];
missing = setdiff(requiredFields, fieldnames(formatStruct));
if ~isempty(missing)
    error('formatStruct is missing required fields: %s', strjoin(missing,', '));
end

% Normalize some format fields to column vectors
fmtCount = double(formatStruct.ChannelCount);
fmtLabels = string(formatStruct.Labels(:));
fmtAz = double(formatStruct.AzimuthDeg(:));
fmtEl = double(formatStruct.ElevationDeg(:));
fmtGroup = string(formatStruct.Group(:));
fmtIsLFE = logical(formatStruct.IsLFE(:));
fmtLoudWeight = double(formatStruct.LoudnessWeight(:));
fmtChannelNumbers = double(formatStruct.ChannelNumbers(:));

% Prepare validation struct with defaults
validation = struct();
validation.IsValid = true;
validation.NumFileChannels = double(numFileChannels);
validation.ExpectedFormatChannels = fmtCount;
validation.HasChannelCountMismatch = false;
validation.HasUnmappedChannels = false;
validation.HasDuplicateSpeakerLabels = false;
validation.Warnings = string.empty(1,0);

% -----------------------
% If existingMap provided, check and use where sensible
% -----------------------
useExisting = false;
if nargin >= 3 && ~isempty(existingMap)
    if ~istable(existingMap)
        validation.IsValid = false;
        validation.Warnings(end+1) = "existingMap must be a table if provided.";
    else
        % Required columns for existingMap
        requiredCols = {'FileChannel','SpeakerLabel','Group','IsLFE','IncludeInLoudness',...
            'IncludeInSpatial','LoudnessWeight','AzimuthDeg','ElevationDeg','Status','Notes'};
        missingCols = setdiff(requiredCols, existingMap.Properties.VariableNames);
        if ~isempty(missingCols)
            validation.IsValid = false;
            validation.Warnings(end+1) = "existingMap is missing required columns: " + strjoin(missingCols,', ');
        else
            useExisting = true;
        end
    end
end

% If previous validation errors from existingMap, still proceed to build defaults but mark invalid
if ~validation.IsValid
    % continue to build a default table so caller has something to inspect
    useExisting = false;
end

% -----------------------
% Build default mapping rows up to max(numFileChannels, fmtCount)
% -----------------------
nRows = max(double(numFileChannels), fmtCount);
FileChannel = (1:nRows)';

% Initialize with defaults
SpeakerLabel = strings(nRows,1);
Group = strings(nRows,1);
IsLFE = false(nRows,1);
IncludeInLoudness = false(nRows,1);
IncludeInSpatial = false(nRows,1);
LoudnessWeight = zeros(nRows,1);
AzimuthDeg = NaN(nRows,1);
ElevationDeg = NaN(nRows,1);
Status = strings(nRows,1);
Notes = strings(nRows,1);

% Map format channels into rows 1:fmtCount
for k = 1:fmtCount
    SpeakerLabel(k) = fmtLabels(k);
    Group(k) = fmtGroup(k);
    IsLFE(k) = fmtIsLFE(k);
    % Default loudness/spatial inclusion
    if fmtIsLFE(k)
        IncludeInLoudness(k) = false;
        IncludeInSpatial(k) = false;
        Notes(k) = "LFE excluded by default; user may enable later.";
    else
        IncludeInLoudness(k) = true;
        IncludeInSpatial(k) = true;
    end
    LoudnessWeight(k) = fmtLoudWeight(k);
    AzimuthDeg(k) = fmtAz(k);
    ElevationDeg(k) = fmtEl(k);
    % Status: for now mark mapped if file has at least that many channels
    if k <= numFileChannels
        Status(k) = "Mapped";
    else
        Status(k) = "Unmapped"; % format channel has no corresponding file channel
    end
end

% Extra file channels beyond format
if numFileChannels > fmtCount
    for k = fmtCount+1:numFileChannels
        SpeakerLabel(k) = "Unassigned_" + string(k);
        Group(k) = "Unassigned";
        IsLFE(k) = false;
        IncludeInLoudness(k) = false;
        IncludeInSpatial(k) = false;
        LoudnessWeight(k) = 0;
        AzimuthDeg(k) = NaN;
        ElevationDeg(k) = NaN;
        Status(k) = "ExtraFileChannel";
        Notes(k) = "Extra file channel not defined in format.";
    end
end

% If numFileChannels < nRows (which equals fmtCount), we will only return rows 1:numFileChannels
% because the table represents file channels. However we still keep info about unmapped format channels
if numFileChannels < nRows
    % Rows beyond numFileChannels represent format channels that the file lacks.
    % We will not include them in the returned channelMapTable (they are not file channels).
    % But mark validation about mismatch/unmapped.
    validation.HasChannelCountMismatch = true;
    validation.HasUnmappedChannels = true;
    validation.Warnings(end+1) = "WAV file has fewer channels (" + string(numFileChannels) + ") than expected for format '" + string(formatStruct.Name) + "' (" + string(fmtCount) + ").";
end

% If numFileChannels >= fmtCount, check if there are extra channels
if numFileChannels > fmtCount
    validation.HasChannelCountMismatch = true;
    validation.HasUnmappedChannels = true;
    validation.Warnings(end+1) = "WAV file has more channels (" + string(numFileChannels) + ") than expected for format '" + string(formatStruct.Name) + "' (" + string(fmtCount) + "). Extra channels labeled 'Unassigned_#'.";
end

% If existingMap is provided and valid, merge it into our initial table for rows 1..numFileChannels
if useExisting
    % Ensure existing map has rows for FileChannel 1..numFileChannels. If not, fill from defaults.
    % Convert existingMap columns to expected types where possible
    ex = existingMap;
    % Find rows in existing map corresponding to file channels 1..numFileChannels
    % If existing map has a FileChannel variable, use it; otherwise assume rows are in order.
    if any(strcmp(existingMap.Properties.VariableNames,'FileChannel'))
        % Align by FileChannel value
        % Create index mapping
        exFC = double(ex.FileChannel(:));
        for idx = 1:double(numFileChannels)
            loc = find(exFC == idx, 1);
            if ~isempty(loc)
                % Overwrite default entries with provided ones
                SpeakerLabel(idx) = string(ex.SpeakerLabel(loc));
                Group(idx) = string(ex.Group(loc));
                IsLFE(idx) = logical(ex.IsLFE(loc));
                IncludeInLoudness(idx) = logical(ex.IncludeInLoudness(loc));
                IncludeInSpatial(idx) = logical(ex.IncludeInSpatial(loc));
                LoudnessWeight(idx) = double(ex.LoudnessWeight(loc));
                AzimuthDeg(idx) = double(ex.AzimuthDeg(loc));
                ElevationDeg(idx) = double(ex.ElevationDeg(loc));
                Status(idx) = string(ex.Status(loc));
                Notes(idx) = string(ex.Notes(loc));
            end
        end
    else
        % Assume row order matches file channels
        nExRows = height(ex);
        useRows = min(nExRows, numFileChannels);
        for idx = 1:useRows
            SpeakerLabel(idx) = string(ex.SpeakerLabel(idx));
            Group(idx) = string(ex.Group(idx));
            IsLFE(idx) = logical(ex.IsLFE(idx));
            IncludeInLoudness(idx) = logical(ex.IncludeInLoudness(idx));
            IncludeInSpatial(idx) = logical(ex.IncludeInSpatial(idx));
            LoudnessWeight(idx) = double(ex.LoudnessWeight(idx));
            AzimuthDeg(idx) = double(ex.AzimuthDeg(idx));
            ElevationDeg(idx) = double(ex.ElevationDeg(idx));
            Status(idx) = string(ex.Status(idx));
            Notes(idx) = string(ex.Notes(idx));
        end
    end
end

% Build final table: only rows that correspond to actual file channels (1..numFileChannels)
sel = (1:double(numFileChannels))';
channelMapTable = table(...
    sel, SpeakerLabel(1:numFileChannels), Group(1:numFileChannels), IsLFE(1:numFileChannels), ...
    IncludeInLoudness(1:numFileChannels), IncludeInSpatial(1:numFileChannels), LoudnessWeight(1:numFileChannels), ...
    AzimuthDeg(1:numFileChannels), ElevationDeg(1:numFileChannels), Status(1:numFileChannels), Notes(1:numFileChannels), ...
    'VariableNames', {'FileChannel','SpeakerLabel','Group','IsLFE','IncludeInLoudness','IncludeInSpatial', ...
    'LoudnessWeight','AzimuthDeg','ElevationDeg','Status','Notes'});

% -----------------------
% Additional validations
% -----------------------
% 1) Duplicate speaker labels excluding Unassigned*
labelsToCheck = string(channelMapTable.SpeakerLabel);
% Treat empty strings as potential unmapped
emptyLabelMask = labelsToCheck == "" | ismissing(labelsToCheck);
if any(emptyLabelMask)
    % Mark unmapped if empty
    validation.HasUnmappedChannels = true;
    validation.Warnings(end+1) = "Some file channels have empty SpeakerLabel values.";
end

% Exclude Unassigned_* from duplicate detection
isUnassigned = startsWith(labelsToCheck, "Unassigned", "IgnoreCase", true);
labelsForDupCheck = labelsToCheck(~isUnassigned & ~emptyLabelMask);
[uniqueLabels, ~, ic] = unique(labelsForDupCheck);
counts = accumarray(ic, 1);
dupMask = counts > 1;
if any(dupMask)
    dupLabels = uniqueLabels(dupMask);
    validation.HasDuplicateSpeakerLabels = true;
    validation.IsValid = false;
    validation.Warnings(end+1) = "Duplicate speaker labels detected: " + strjoin(dupLabels,', ');
else
    validation.HasDuplicateSpeakerLabels = false;
end

% If any Status is "Unmapped" or "ExtraFileChannel" set HasUnmappedChannels true
if any(channelMapTable.Status == "Unmapped") || any(channelMapTable.Status == "ExtraFileChannel")
    validation.HasUnmappedChannels = true;
end

% Final IsValid: if there are warnings that make the mapping invalid (we flagged some earlier)
% Keep IsValid false if HasDuplicateSpeakerLabels or existingMap invalid. Otherwise true.
if validation.HasDuplicateSpeakerLabels
    validation.IsValid = false;
end

% Ensure Warnings is unique and in stable order
if ~isempty(validation.Warnings)
    validation.Warnings = unique(validation.Warnings, 'stable');
else
    validation.Warnings = string.empty(1,0);
end

end