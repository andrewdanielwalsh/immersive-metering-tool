function ax = plotSoundField3D(spatialData, plotMode, ax)
%PLOTSOUNDFIELD3D Plot spatial energy using gradient-colored line segments.
%
% Project:
%   Immersive Metering Tool
%
% Purpose:
%   Display spatial energy as a continuous line with intensity color
%   grading, plus speaker and listener reference points.
%
% Supported modes:
%   "3D"
%   "TopDown"
%   "Side"
%   "EnergyBars"
%
% Notes:
%   The spatial coordinates are normalized speaker-field coordinates,
%   not room-meter coordinates.

    %% Validate input

    if nargin < 1 || isempty(spatialData) || ~isstruct(spatialData)
        error("plotSoundField3D:InvalidInput", ...
            "spatialData must be the struct returned by computeSpatialEnergy.");
    end

    if nargin < 2 || isempty(plotMode)
        plotMode = "3D";
    end

    plotMode = lower(strtrim(string(plotMode)));

    if nargin < 3 || isempty(ax) || ~isvalid(ax)
        figure("Name", "Immersive Metering Tool - Sound Field");
        ax = axes;
    end

    cla(ax);

    if ~isfield(spatialData, "FrameTable") || ~istable(spatialData.FrameTable)
        displayNoDataMessage(ax, "No FrameTable found in spatialData.");
        return;
    end

    if height(spatialData.FrameTable) < 1
        displayNoDataMessage(ax, "Spatial FrameTable is empty.");
        return;
    end

    %% Plot mode switch

    switch plotMode
        case {"3d", "field", "trajectory"}
            plot3DGradientTrajectory(ax, spatialData);

        case {"topdown", "top", "xy"}
            plotTopDownGradientTrajectory(ax, spatialData);

        case {"side", "yz"}
            plotSideGradientTrajectory(ax, spatialData);

        case {"energybars", "bars", "groups"}
            plotEnergyBars(ax, spatialData);

        otherwise
            error("plotSoundField3D:InvalidPlotMode", ...
                "plotMode must be '3D', 'TopDown', 'Side', or 'EnergyBars'.");
    end

    drawnow;
end

%% Main plot functions

function plot3DGradientTrajectory(ax, spatialData)

    [x, y, z, intensityDB] = extractCentroidData(spatialData.FrameTable);

    if numel(x) < 2
        displayNoDataMessage(ax, "Not enough valid spatial points to draw a trajectory.");
        return;
    end

    hold(ax, "on");

    plotSpeakerReferences3D(ax, spatialData);
    plotListenerReference3D(ax);

    lineWidth = 0.65;
    plotGradientLineSegments3D(ax, x, y, z, intensityDB, lineWidth);

    xlabel(ax, "X  Left / Right");
    ylabel(ax, "Y  Rear / Front");
    zlabel(ax, "Z  Height");

    title(ax, "3D Spatial Energy Trajectory");

    grid(ax, "on");
    box(ax, "on");
    axis(ax, "equal");
    view(ax, 42, 24);

    applySpatialLimits3D(ax, x, y, z, spatialData);
    applySpectrogramColorbar(ax, intensityDB, "Energy (dBFS)");

    hold(ax, "off");
end

function plotTopDownGradientTrajectory(ax, spatialData)

    [x, y, ~, intensityDB] = extractCentroidData(spatialData.FrameTable);

    if numel(x) < 2
        displayNoDataMessage(ax, "Not enough valid top-down spatial points.");
        return;
    end

    hold(ax, "on");

    plotSpeakerReferences2D(ax, spatialData, "topdown");
    plotListenerReference2D(ax);

    lineWidth = 0.65;
    plotGradientLineSegments2D(ax, x, y, intensityDB, lineWidth);

    xlabel(ax, "X  Left / Right");
    ylabel(ax, "Y  Rear / Front");

    title(ax, "Top-Down Spatial Energy Trajectory");

    grid(ax, "on");
    box(ax, "on");
    axis(ax, "equal");

    applySpatialLimitsTopDown(ax, x, y, spatialData);
    applySpectrogramColorbar(ax, intensityDB, "Energy (dBFS)");

    hold(ax, "off");
end

function plotSideGradientTrajectory(ax, spatialData)

    [~, y, z, intensityDB] = extractCentroidData(spatialData.FrameTable);

    if numel(y) < 2
        displayNoDataMessage(ax, "Not enough valid side-view spatial points.");
        return;
    end

    hold(ax, "on");

    plotSpeakerReferences2D(ax, spatialData, "side");
    plotListenerReferenceSide(ax);

    lineWidth = 0.65;
    plotGradientLineSegments2D(ax, y, z, intensityDB, lineWidth);

    xlabel(ax, "Y  Rear / Front");
    ylabel(ax, "Z  Height");

    title(ax, "Side Spatial Energy Trajectory");

    grid(ax, "on");
    box(ax, "on");
    axis(ax, "equal");

    applySpatialLimitsSide(ax, y, z, spatialData);
    applySpectrogramColorbar(ax, intensityDB, "Energy (dBFS)");

    hold(ax, "off");
end

function plotEnergyBars(ax, spatialData)

    if ~isfield(spatialData, "GroupTable") || ~istable(spatialData.GroupTable)
        displayNoDataMessage(ax, "No GroupTable found for energy bars.");
        return;
    end

    groupTable = spatialData.GroupTable;

    if isempty(groupTable) || height(groupTable) < 1
        displayNoDataMessage(ax, "Group energy table is empty.");
        return;
    end

    if ~all(ismember(["Group","EnergyPercent"], string(groupTable.Properties.VariableNames)))
        displayNoDataMessage(ax, "GroupTable must contain Group and EnergyPercent.");
        return;
    end

    bar(ax, categorical(groupTable.Group), groupTable.EnergyPercent);

    ylabel(ax, "Energy (%)");
    xlabel(ax, "Speaker Group");
    title(ax, "Mean Energy by Speaker Group");

    grid(ax, "on");
end

%% Gradient segment plotting

function plotGradientLineSegments3D(ax, x, y, z, intensityDB, lineWidth)
%PLOTGRADIENTLINESEGMENTS3D Reliable gradient line for normal axes/uiaxes.

    cmap = getSpectrogramColormap(256);
    [cMin, cMax] = getColorLimits(intensityDB);

    for k = 1:numel(x)-1
        segmentIntensity = mean([intensityDB(k), intensityDB(k+1)], "omitnan");
        colorIndex = mapValueToColorIndex(segmentIntensity, cMin, cMax, size(cmap, 1));
        segmentColor = cmap(colorIndex, :);

        plot3(ax, ...
            x(k:k+1), ...
            y(k:k+1), ...
            z(k:k+1), ...
            "LineWidth", lineWidth, ...
            "Color", segmentColor);
    end

    colormap(ax, cmap);
    applyColorLimits(ax, [cMin cMax]);
end

function plotGradientLineSegments2D(ax, x, y, intensityDB, lineWidth)
%PLOTGRADIENTLINESEGMENTS2D Reliable 2D gradient line.

    cmap = getSpectrogramColormap(256);
    [cMin, cMax] = getColorLimits(intensityDB);

    for k = 1:numel(x)-1
        segmentIntensity = mean([intensityDB(k), intensityDB(k+1)], "omitnan");
        colorIndex = mapValueToColorIndex(segmentIntensity, cMin, cMax, size(cmap, 1));
        segmentColor = cmap(colorIndex, :);

        plot(ax, ...
            x(k:k+1), ...
            y(k:k+1), ...
            "LineWidth", lineWidth, ...
            "Color", segmentColor);
    end

    colormap(ax, cmap);
    applyColorLimits(ax, [cMin cMax]);
end

function cmap = getSpectrogramColormap(n)
%GETSPECTROGRAMCOLORMAP Use turbo if available, otherwise fall back to parula.

    if exist("turbo", "file") == 2 || exist("turbo", "builtin") == 5
        cmap = turbo(n);
    else
        cmap = parula(n);
    end
end

function [cMin, cMax] = getColorLimits(values)

    values = values(:);
    values = values(isfinite(values));

    if isempty(values)
        cMin = 0;
        cMax = 1;
        return;
    end

    cMin = min(values);
    cMax = max(values);

    if cMax <= cMin
        cMin = cMin - 1;
        cMax = cMax + 1;
    end
end

function index = mapValueToColorIndex(value, cMin, cMax, numColors)

    if ~isfinite(value)
        index = 1;
        return;
    end

    value = max(cMin, min(cMax, value));
    normalizedValue = (value - cMin) / (cMax - cMin);

    index = round(1 + normalizedValue * (numColors - 1));
    index = max(1, min(numColors, index));
end

function applySpectrogramColorbar(ax, intensityDB, labelText)

    cmap = getSpectrogramColormap(256);
    colormap(ax, cmap);

    [cMin, cMax] = getColorLimits(intensityDB);
    applyColorLimits(ax, [cMin cMax]);

    cb = colorbar(ax);
    cb.Label.String = labelText;
end

function applyColorLimits(ax, limits)

    try
        clim(ax, limits);
    catch
        caxis(ax, limits);
    end
end

%% Speaker and listener references

function plotSpeakerReferences3D(ax, spatialData)

    [sx, sy, sz, labels] = extractSpeakerData(spatialData);

    if isempty(sx)
        return;
    end

    scatter3(ax, ...
        sx, sy, sz, ...
        45, ...
        [0.20 0.20 0.20], ...
        "^", ...
        "filled");

    for k = 1:numel(sx)
        text(ax, ...
            sx(k), sy(k), sz(k), ...
            " " + string(labels(k)), ...
            "FontSize", 8, ...
            "Color", [0.1 0.1 0.1]);
    end
end

function plotSpeakerReferences2D(ax, spatialData, viewMode)

    [sx, sy, sz, labels] = extractSpeakerData(spatialData);

    if isempty(sx)
        return;
    end

    switch lower(string(viewMode))
        case "topdown"
            scatter(ax, ...
                sx, sy, ...
                40, ...
                [0.20 0.20 0.20], ...
                "^", ...
                "filled");

            for k = 1:numel(sx)
                text(ax, ...
                    sx(k), sy(k), ...
                    " " + string(labels(k)), ...
                    "FontSize", 8, ...
                    "Color", [0.1 0.1 0.1]);
            end

        case "side"
            scatter(ax, ...
                sy, sz, ...
                40, ...
                [0.20 0.20 0.20], ...
                "^", ...
                "filled");

            for k = 1:numel(sy)
                text(ax, ...
                    sy(k), sz(k), ...
                    " " + string(labels(k)), ...
                    "FontSize", 8, ...
                    "Color", [0.1 0.1 0.1]);
            end
    end
end

function plotListenerReference3D(ax)

    scatter3(ax, ...
        0, 0, 0, ...
        40, ...
        [0 0 0], ...
        "o", ...
        "filled");

    text(ax, 0, 0, 0, ...
        " Listener", ...
        "FontWeight", "bold", ...
        "Color", [0 0 0]);
end

function plotListenerReference2D(ax)

    scatter(ax, ...
        0, 0, ...
        40, ...
        [0 0 0], ...
        "o", ...
        "filled");

    text(ax, 0, 0, ...
        " Listener", ...
        "FontWeight", "bold", ...
        "Color", [0 0 0]);
end

function plotListenerReferenceSide(ax)

    scatter(ax, ...
        0, 0, ...
        40, ...
        [0 0 0], ...
        "o", ...
        "filled");

    text(ax, 0, 0, ...
        " Listener", ...
        "FontWeight", "bold", ...
        "Color", [0 0 0]);
end

%% Data extraction

function [x, y, z, intensityDB] = extractCentroidData(frameTable)

    names = string(frameTable.Properties.VariableNames);

    requiredColumns = ["CentroidX", "CentroidY", "CentroidZ"];

    if ~all(ismember(requiredColumns, names))
        x = [];
        y = [];
        z = [];
        intensityDB = [];
        return;
    end

    x = double(frameTable.CentroidX(:));
    y = double(frameTable.CentroidY(:));
    z = double(frameTable.CentroidZ(:));

    if ismember("TotalEnergyDBFS", names)
        intensityDB = double(frameTable.TotalEnergyDBFS(:));
    elseif ismember("TotalEnergy", names)
        intensityDB = 10 * log10(double(frameTable.TotalEnergy(:)) + eps);
    else
        intensityDB = zeros(size(x));
    end

    validMask = isfinite(x) & ...
                isfinite(y) & ...
                isfinite(z) & ...
                isfinite(intensityDB);

    x = x(validMask);
    y = y(validMask);
    z = z(validMask);
    intensityDB = intensityDB(validMask);

    if ~isempty(intensityDB)
        maxEnergy = max(intensityDB);
        keepMask = intensityDB >= maxEnergy - 80;

        x = x(keepMask);
        y = y(keepMask);
        z = z(keepMask);
        intensityDB = intensityDB(keepMask);
    end
end

function [sx, sy, sz, labels] = extractSpeakerData(spatialData)

    sx = [];
    sy = [];
    sz = [];
    labels = strings(0,1);

    if ~isfield(spatialData, "ChannelTable") || ~istable(spatialData.ChannelTable)
        return;
    end

    channelTable = spatialData.ChannelTable;
    names = string(channelTable.Properties.VariableNames);

    requiredColumns = ["X", "Y", "Z", "SpeakerLabel"];

    if ~all(ismember(requiredColumns, names))
        return;
    end

    sx = double(channelTable.X(:));
    sy = double(channelTable.Y(:));
    sz = double(channelTable.Z(:));
    labels = string(channelTable.SpeakerLabel(:));

    validMask = isfinite(sx) & isfinite(sy) & isfinite(sz);

    sx = sx(validMask);
    sy = sy(validMask);
    sz = sz(validMask);
    labels = labels(validMask);
end

%% Axis helpers

function applySpatialLimits3D(ax, x, y, z, spatialData)

    [sx, sy, sz, ~] = extractSpeakerData(spatialData);

    allX = [x(:); sx(:); 0];
    allY = [y(:); sy(:); 0];
    allZ = [z(:); sz(:); 0];

    allX = allX(isfinite(allX));
    allY = allY(isfinite(allY));
    allZ = allZ(isfinite(allZ));

    xPad = computePadding(allX);
    yPad = computePadding(allY);
    zPad = computePadding(allZ);

    xlim(ax, [min(allX)-xPad, max(allX)+xPad]);
    ylim(ax, [min(allY)-yPad, max(allY)+yPad]);
    zlim(ax, [min(allZ)-zPad, max(allZ)+zPad]);
end

function applySpatialLimitsTopDown(ax, x, y, spatialData)

    [sx, sy, ~, ~] = extractSpeakerData(spatialData);

    allX = [x(:); sx(:); 0];
    allY = [y(:); sy(:); 0];

    allX = allX(isfinite(allX));
    allY = allY(isfinite(allY));

    xPad = computePadding(allX);
    yPad = computePadding(allY);

    xlim(ax, [min(allX)-xPad, max(allX)+xPad]);
    ylim(ax, [min(allY)-yPad, max(allY)+yPad]);
end

function applySpatialLimitsSide(ax, y, z, spatialData)

    [~, sy, sz, ~] = extractSpeakerData(spatialData);

    allY = [y(:); sy(:); 0];
    allZ = [z(:); sz(:); 0];

    allY = allY(isfinite(allY));
    allZ = allZ(isfinite(allZ));

    yPad = computePadding(allY);
    zPad = computePadding(allZ);

    xlim(ax, [min(allY)-yPad, max(allY)+yPad]);
    ylim(ax, [min(allZ)-zPad, max(allZ)+zPad]);
end

function p = computePadding(v)

    v = double(v(:));
    v = v(isfinite(v));

    if isempty(v)
        p = 0.5;
        return;
    end

    span = max(v) - min(v);

    if span <= 0
        p = 0.5;
    else
        p = 0.10 * span;
    end
end

function displayNoDataMessage(ax, messageText)

    cla(ax);

    text(ax, ...
        0.5, 0.5, string(messageText), ...
        "Units", "normalized", ...
        "HorizontalAlignment", "center", ...
        "VerticalAlignment", "middle", ...
        "FontSize", 13, ...
        "FontWeight", "bold");

    axis(ax, "off");
end