function fmt = getFormatMap(formatName)
%GETFORMATMAP Return one default format preset by name.
%
% Examples:
%   fmt = getFormatMap("7.1.4");
%   fmt = getFormatMap("4.0");
%   fmt = getFormatMap("quad");
%   fmt = getFormatMap("7.1.2");

    if nargin < 1 || isempty(formatName)
        formatName = "7.1.4";
    end

    requestedName = normalizeFormatName(formatName);

    formats = defaultFormats();

    availableNames = strings(numel(formats), 1);

    for k = 1:numel(formats)
        availableNames(k) = normalizeFormatName(formats(k).Name);
    end

    matchIndex = find(availableNames == requestedName, 1, "first");

    if isempty(matchIndex)
        validNames = strings(numel(formats), 1);

        for k = 1:numel(formats)
            validNames(k) = formats(k).Name;
        end

        error("getFormatMap:UnknownFormat", ...
            "Unknown format '%s'. Available formats are: %s", ...
            string(formatName), ...
            strjoin(validNames.', ", "));
    end

    fmt = formats(matchIndex);
end

function normalizedName = normalizeFormatName(formatName)
%NORMALIZEFORMATNAME Support aliases and user-friendly names.

    txt = lower(strtrim(string(formatName)));

    txt = replace(txt, " ", "");
    txt = replace(txt, "_", "");
    txt = replace(txt, "-", "");
    txt = replace(txt, "/", "");

    switch txt
        case {"mono", "1", "1.0"}
            normalizedName = "mono";

        case {"stereo", "2", "2.0"}
            normalizedName = "stereo";

        case {"4.0", "40", "quad", "quadraphonic", "4.0quad"}
            normalizedName = "4.0";

        case {"5.1", "51"}
            normalizedName = "5.1";

        case {"7.1", "71"}
            normalizedName = "7.1";

        case {"7.1.2", "712"}
            normalizedName = "7.1.2";

        case {"7.1.4", "714"}
            normalizedName = "7.1.4";

        otherwise
            normalizedName = txt;
    end
end