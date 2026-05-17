function ax = plotSpeakerDelays(roomModel, ax)
%PLOTSPEAKERDELAYS Plot delay compensation values by speaker.
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Show useful speaker delay compensation values.
%
% Delay meaning:
%   The farthest speaker is the timing reference.
%   Closer speakers receive added delay so arrivals align at the listener.

    %% Validate input

    if nargin < 1 || isempty(roomModel) || ~isstruct(roomModel)
        error("plotSpeakerDelays:InvalidRoomModel", ...
            "roomModel must be a nonempty struct.");
    end

    if nargin < 2 || isempty(ax) || ~isvalid(ax)
        figure("Name", "Speaker Delays");
        ax = axes;
    end

    cla(ax);

    if ~isfield(roomModel, "SpeakerTable") || ~istable(roomModel.SpeakerTable)
        title(ax, "Speaker Delays - No speaker table available");
        return;
    end

    speakerTable = roomModel.SpeakerTable;
    names = string(speakerTable.Properties.VariableNames);

    if ~ismember("SpeakerLabel", names) || ~ismember("DelayToAddMilliseconds", names)
        title(ax, "Speaker Delays - Delay data unavailable");
        return;
    end

    labels = string(speakerTable.SpeakerLabel(:));
    delayToAdd = double(speakerTable.DelayToAddMilliseconds(:));

    if ismember("DistanceMeters", names)
        distances = double(speakerTable.DistanceMeters(:));
    else
        distances = NaN(size(delayToAdd));
    end

    if ismember("ReferenceSpeaker", names)
        referenceSpeaker = convertToLogical(speakerTable.ReferenceSpeaker);
    else
        referenceSpeaker = false(size(delayToAdd));
    end

    validMask = isfinite(delayToAdd);

    if ~any(validMask)
        title(ax, "Speaker Delays - No valid delay values");
        return;
    end

    labels = labels(validMask);
    delayToAdd = delayToAdd(validMask);
    distances = distances(validMask);
    referenceSpeaker = referenceSpeaker(validMask);

    %% Plot

    bar(ax, delayToAdd);

    xticks(ax, 1:numel(labels));
    xticklabels(ax, labels);
    xtickangle(ax, 45);

    ylabel(ax, "Delay to Add (ms)");
    xlabel(ax, "Speaker");

    title(ax, buildDelayTitle(roomModel));

    grid(ax, "on");
    box(ax, "on");

    %% Add value labels

    yMax = max(delayToAdd);

    if ~isfinite(yMax) || yMax <= 0
        yMax = 1;
    end

    ylim(ax, [0, yMax * 1.20]);

    for k = 1:numel(delayToAdd)
        labelText = sprintf("%.2f ms", delayToAdd(k));

        if referenceSpeaker(k)
            labelText = labelText + " ref";
        end

        text(ax, k, delayToAdd(k), ...
            labelText, ...
            "HorizontalAlignment", "center", ...
            "VerticalAlignment", "bottom", ...
            "FontSize", 8);
    end

    %% Add distance summary as subtitle-style text

    finiteDistances = distances(isfinite(distances));

    if ~isempty(finiteDistances)
        distanceSummary = sprintf( ...
            "Distance range: %.2f m to %.2f m", ...
            min(finiteDistances), ...
            max(finiteDistances));

        text(ax, 0.01, 0.98, ...
            distanceSummary, ...
            "Units", "normalized", ...
            "HorizontalAlignment", "left", ...
            "VerticalAlignment", "top", ...
            "FontSize", 9, ...
            "FontWeight", "bold");
    end

    drawnow;
end

%% Helpers

function titleText = buildDelayTitle(roomModel)

    titleText = "Speaker Delay Compensation";

    if isfield(roomModel, "Validation") && isstruct(roomModel.Validation)
        v = roomModel.Validation;

        if isfield(v, "DelayReferenceSpeakerLabel")
            titleText = titleText + " | Reference: " + string(v.DelayReferenceSpeakerLabel);
        end

        if isfield(v, "MaxDelayToAddMilliseconds")
            if isfinite(v.MaxDelayToAddMilliseconds)
                titleText = titleText + ...
                    " | Max Add: " + sprintf("%.2f ms", v.MaxDelayToAddMilliseconds);
            end
        elseif isfield(v, "MaxDelayMilliseconds")
            if isfinite(v.MaxDelayMilliseconds)
                titleText = titleText + ...
                    " | Max: " + sprintf("%.2f ms", v.MaxDelayMilliseconds);
            end
        end
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