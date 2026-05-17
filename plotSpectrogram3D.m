function ax = plotSpectrogram3D(spectrogramData, plotMode, ax)
%PLOTSPECTROGRAM3D Plot 2D or 3D spectrogram data.
%
% Project:
%   Immersive Metering Tool
%
% Inputs:
%   spectrogramData - Output struct from computeSpectrogram3D()
%   plotMode        - "3D", "2D", or "TopDown"
%   ax              - Optional axes handle
%
% Output:
%   ax              - Axes used for plotting

%% Validate input

if nargin < 1 || isempty(spectrogramData) || ~isstruct(spectrogramData)
    error("plotSpectrogram3D:InvalidInput", ...
        "spectrogramData must be the struct returned by computeSpectrogram3D.");
end

requiredFields = [
    "TimeSeconds"
    "FrequencyHz"
    "PowerDB"
    "SourceName"
    ];

for k = 1:numel(requiredFields)
    if ~isfield(spectrogramData, requiredFields(k))
        error("plotSpectrogram3D:InvalidInput", ...
            "spectrogramData is missing required field: %s", requiredFields(k));
    end
end

if nargin < 2 || isempty(plotMode)
    plotMode = "3D";
end

plotMode = lower(strtrim(string(plotMode)));

if nargin < 3 || isempty(ax) || ~isvalid(ax)
    figure("Name", "Immersive Metering Tool - Spectrogram");
    ax = axes;
end

%% Extract data

t = spectrogramData.TimeSeconds;
f = spectrogramData.FrequencyHz;
p = spectrogramData.PowerDB;

%% Plot

cla(ax);

switch plotMode
    case {"3d", "surface"}
        surf(ax, t, f, p, ...
            "EdgeColor", "none", ...
            "FaceColor", "interp");

        view(ax, 45, 60);
        xlabel(ax, "Time (s)");
        ylabel(ax, "Frequency (Hz)");
        zlabel(ax, "Power (dB)");

    case {"2d", "image", "heatmap"}
        imagesc(ax, t, f, p);
        set(ax, "YDir", "normal");

        view(ax, 2);
        xlabel(ax, "Time (s)");
        ylabel(ax, "Frequency (Hz)");

    case {"topdown", "top down", "top"}
        surf(ax, t, f, p, ...
            "EdgeColor", "none", ...
            "FaceColor", "interp");

        view(ax, 2);
        xlabel(ax, "Time (s)");
        ylabel(ax, "Frequency (Hz)");

    otherwise
        error("plotSpectrogram3D:InvalidPlotMode", ...
            "plotMode must be '3D', '2D', or 'TopDown'.");
end

title(ax, "Spectrogram - " + string(spectrogramData.SourceName));
axis(ax, "tight");
grid(ax, "on");

colorbar(ax);

end