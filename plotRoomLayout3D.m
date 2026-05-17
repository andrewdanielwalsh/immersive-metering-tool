function ax = plotRoomLayout3D(roomModel, ax)
%PLOTROOMLAYOUT3D Clean room geometry plot.
%
% Shows only:
%   - room boundary
%   - listener position
%   - speaker positions
%   - speaker label + distance
%
% Delay and detailed speaker data belong in the Speaker Delays tab.

    if nargin < 1 || isempty(roomModel) || ~isstruct(roomModel)
        error("plotRoomLayout3D:InvalidRoomModel", ...
            "roomModel must be a nonempty struct.");
    end

    if nargin < 2 || isempty(ax) || ~isvalid(ax)
        figure("Name", "Room Layout");
        ax = axes;
    end

    requiredFields = ["RoomDimensionsMeters", "ListenerPositionMeters", "SpeakerTable"];

    for k = 1:numel(requiredFields)
        if ~isfield(roomModel, requiredFields(k))
            error("plotRoomLayout3D:MissingField", ...
                "roomModel is missing required field: %s", requiredFields(k));
        end
    end

    if ~istable(roomModel.SpeakerTable)
        error("plotRoomLayout3D:InvalidSpeakerTable", ...
            "roomModel.SpeakerTable must be a MATLAB table.");
    end

    roomDimensions = double(roomModel.RoomDimensionsMeters(:).');

    roomLength = roomDimensions(1);
    roomWidth = roomDimensions(2);
    roomHeight = roomDimensions(3);

    listenerPosition = double(roomModel.ListenerPositionMeters(:).');

    speakerTable = normalizeSpeakerTableForRoomPlot( ...
        roomModel.SpeakerTable, ...
        listenerPosition);

    cla(ax);
    hold(ax, "on");

    plotRoomBox(ax, roomLength, roomWidth, roomHeight);
    plotListener(ax, listenerPosition);

    for k = 1:height(speakerTable)
        plotSpeaker(ax, speakerTable(k, :), listenerPosition);
    end

    xlabel(ax, "X Width (m)");
    ylabel(ax, "Y Length (m)");
    zlabel(ax, "Z Height (m)");

    title(ax, buildRoomTitle(roomModel));

    xlim(ax, [0 roomWidth]);
    ylim(ax, [0 roomLength]);
    zlim(ax, [0 roomHeight]);

    grid(ax, "on");
    box(ax, "on");
    axis(ax, "equal");

    view(ax, 38, 24);

    hold(ax, "off");
    drawnow;
end

%% Helpers

function speakerTable = normalizeSpeakerTableForRoomPlot(speakerTable, listenerPosition)

    numSpeakers = height(speakerTable);
    names = string(speakerTable.Properties.VariableNames);

    if ~ismember("SpeakerLabel", names)
        speakerTable.SpeakerLabel = "Spk" + string((1:numSpeakers).');
    end

    if ~ismember("IsLFE", names)
        speakerTable.IsLFE = false(numSpeakers, 1);
    end

    if ~ismember("X", names) || ~ismember("Y", names) || ~ismember("Z", names)
        error("plotRoomLayout3D:MissingCoordinates", ...
            "SpeakerTable must contain X, Y, and Z columns.");
    end

    speakerTable.SpeakerLabel = string(speakerTable.SpeakerLabel(:));
    speakerTable.IsLFE = convertToLogical(speakerTable.IsLFE);

    speakerTable.X = double(speakerTable.X(:));
    speakerTable.Y = double(speakerTable.Y(:));
    speakerTable.Z = double(speakerTable.Z(:));

    if ismember("DistanceMeters", names)
        distanceMeters = double(speakerTable.DistanceMeters(:));
    else
        dx = speakerTable.X - listenerPosition(1);
        dy = speakerTable.Y - listenerPosition(2);
        dz = speakerTable.Z - listenerPosition(3);
        distanceMeters = sqrt(dx.^2 + dy.^2 + dz.^2);
    end

    speakerTable.DistanceMeters = distanceMeters;
end

function plotRoomBox(ax, roomLength, roomWidth, roomHeight)

    x0 = 0;
    x1 = roomWidth;

    y0 = 0;
    y1 = roomLength;

    z0 = 0;
    z1 = roomHeight;

    corners = [
        x0 y0 z0
        x1 y0 z0
        x1 y1 z0
        x0 y1 z0
        x0 y0 z1
        x1 y0 z1
        x1 y1 z1
        x0 y1 z1
    ];

    edges = [
        1 2
        2 3
        3 4
        4 1
        5 6
        6 7
        7 8
        8 5
        1 5
        2 6
        3 7
        4 8
    ];

    for k = 1:size(edges, 1)
        p1 = corners(edges(k, 1), :);
        p2 = corners(edges(k, 2), :);

        plot3(ax, ...
            [p1(1), p2(1)], ...
            [p1(2), p2(2)], ...
            [p1(3), p2(3)], ...
            "LineWidth", 1.0, ...
            "Color", [0.25 0.25 0.25]);
    end

    plot3(ax, ...
        [x0 x1 x1 x0 x0], ...
        [y0 y0 y1 y1 y0], ...
        [z0 z0 z0 z0 z0], ...
        "LineWidth", 1.25, ...
        "Color", [0.10 0.10 0.10]);
end

function plotListener(ax, listenerPosition)

    x = listenerPosition(1);
    y = listenerPosition(2);
    z = listenerPosition(3);

    plot3(ax, x, y, z, ...
        "o", ...
        "MarkerSize", 9, ...
        "MarkerFaceColor", [0 0 0], ...
        "MarkerEdgeColor", [0 0 0], ...
        "LineStyle", "none");

    text(ax, x, y, z, ...
        "  Listener", ...
        "FontWeight", "bold", ...
        "FontSize", 10, ...
        "Color", [0 0 0], ...
        "VerticalAlignment", "bottom");
end

function plotSpeaker(ax, row, listenerPosition)

    x = row.X;
    y = row.Y;
    z = row.Z;

    label = string(row.SpeakerLabel);
    distanceMeters = double(row.DistanceMeters);
    isLFE = logical(row.IsLFE);

    if isLFE
        markerStyle = "s";
        markerColor = [0.25 0.25 0.25];
    else
        markerStyle = "^";
        markerColor = [0.10 0.35 0.95];
    end

    plot3(ax, x, y, z, ...
        markerStyle, ...
        "MarkerSize", 8, ...
        "MarkerFaceColor", markerColor, ...
        "MarkerEdgeColor", [0 0 0], ...
        "LineStyle", "none");

    plot3(ax, ...
        [listenerPosition(1), x], ...
        [listenerPosition(2), y], ...
        [listenerPosition(3), z], ...
        "LineStyle", ":", ...
        "LineWidth", 0.55, ...
        "Color", [0.65 0.65 0.65]);

    if isfinite(distanceMeters)
        labelText = sprintf("%s\n%.2f m", label, distanceMeters);
    else
        labelText = sprintf("%s\nn/a m", label);
    end

    text(ax, x, y, z, ...
        "  " + string(labelText), ...
        "FontSize", 8, ...
        "Color", [0.05 0.05 0.05], ...
        "VerticalAlignment", "bottom");
end

function titleText = buildRoomTitle(roomModel)

    if isfield(roomModel, "RoomDimensionsMeters")
        d = double(roomModel.RoomDimensionsMeters(:).');

        titleText = sprintf( ...
            "Room Layout | %.2f m L × %.2f m W × %.2f m H", ...
            d(1), d(2), d(3));
    else
        titleText = "Room Layout";
    end

    if isfield(roomModel, "FormatName")
        titleText = string(titleText) + " | " + string(roomModel.FormatName);
    end

    if isfield(roomModel, "PlacementStandardName")
        titleText = string(titleText) + " | " + string(roomModel.PlacementStandardName);
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