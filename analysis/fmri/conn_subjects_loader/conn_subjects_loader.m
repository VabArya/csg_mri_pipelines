function conn_subjects_loader()
% conn_subjects_loader
% Batch load all groups, subjects and sessions from a given directory root into CONN. This saves quite a lot of time.
% The script can then just show the CONN GUI and you do the rest, or automate and process everything and show you CONN GUI only when the results are available.
% You can also resume your job if there is an error or if you CTRL-C (but don't rely too much on it, data can be corrupted). Resume can also be used if you add new subjects.
% This script expects the subjects data to be already preprocessed by your own means (or you can build the CONN project and use the CONN preprocessing pipeline, up to you...).
%
% This script's philosophy is similar to unix/linux: everything is a file. So the entire CONN project is built from your directory layout. This choice was made because it is easier to reorganize folders (and cleaner) than to recode a script to follow the different layout: anybody can move files around, but not everyone can code a MATLAB script.
% The tree structure from the root must follow the following structure:
% /root_path/group_id/subject_id/data/session_id/(mprage|rest)/*.(img|hdr|nii) -- Note: mprage for structural MRI, rest for fMRI
% Any experiment following this tree structure will be accepted and converted to a CONN project automagically for you.
%
% Note that BATCH.Setup.preprocessing is not used here as the data is expected to be already preprocessed by your own means (SPM, Dartel/VBM/CAT, custom pipeline, etc.), but using raw data you can preprocess from the GUI.
% If you need to modify this script, take a look at the conn_batch_workshop_nyudataset.m script provided with CONN, it's a very good example that inspired this script.
%
% This script supports 3rd level analysis (multi-subjects and multi-sessions).
%
% by Stephen Larroque
% Created on 2016-04-11
% Tested on conn15h, conn16b, conn17f and conn18a on data preprocessed with VBM8, CAT12, SPM12 OldSeg and with raw data not preprocessed (in this case, set loading_mode to 0)
% v1.1.4
%
% Licensed under MIT LICENSE
% Copyleft 2016-2019 Stephen Karl Larroque
% Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
% The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%
% TODO:
% * Try to have Dynamic FC for multi-datasets run.
% * Add CSV reading to automatically input 2nd-level covariates like age or sex.
% * save an example CONN_x into .mat to show the expected structure (useful if need to debug).
% * support BIDS format
% * Implement modification/updating of previous CONN projects by using conn_batch (eg, conn_batch('Setup.functionals',myfiles);) instead of first creating a struct (which always overwrites the whole project). See http://www.nitrc.org/forum/forum.php?thread_id=7382&forum_id=1144
% * add erosion for struct_additional_rois when/if it gets implemented for all rois (and not just for GM/WM/CSF as is currently the case)
% * add another mode to detect session: by folder name, and assign to respective session id (instead of adding in order), this would allow the setup of experiments with missing sessions (ie, where subjects have some sessions but not others)
%
% TIPS:
% * After the CONN project loads, make sure to:
%   * Check the data ("Display single-slice for all subjects (montage)" and other manual checks).
%   * Generate ROI masks for Grey Matter, White Matter and CSF (click on ROIs, then select Grey Matter, then click on Erosion Settings, then click OK to everything, then select White matter and do the same... - Note that you cannot select Grey Matter and White Matter and CSF at the same time, because the erosion settings are different: if you do select them all at once, the erosion settings won't be correct).
%   * Rename the conditions so that it is easier for you later to make contrasts without doing a mistake of interpretation.
%   * Check the options you want (eg, generating additional files for later post-processing or sanity checks).
%   * Launch the preprocessing and/or analysis (menu: Tools > Run > Setup/Denoising/1st-level analyses), with the possibility with CONN 18a to run on "Distributed computing" (parallel processing) on all platforms.
% * At the end of analysis, you can add the 2nd-level covariates (you don't need to do it before the analysis).
%

% ------ PARAMETERS HERE
% -- General parameters
TR = 2.46;  % can also input a vector if your subjects have different TR, eg: [ 2.0 2.15*ones(1, 14) 2.15*ones(1, 13) ]
conn_file = fullfile(pwd, 'conn_project_1');  % where to store the temporary project file that will be used to load the subjects into CONN (by default in the same folder as where the commandline is run)
conn_ver = 18; % Put here the CONN version you use (just the number, not the letter)
root_path = 'X:\Path\To\Data'; % Where your neuroimaging data is located in the following BIDS-like hierarchy: /root_path/group_id/subject_id/data/session_id/(mprage|rest)/*.(img|hdr|nii) -- Note: mprage for structural MRI, rest for fMRI
path_to_spm = 'C:\matlab_tools\spm12';
path_to_conn = 'C:\matlab_tools\conn18b'; % avoid CONN16a and prefer CONN16b or even CONN17f, as CONN16a gives weird results (and sanity checks for DMN do not pass)
path_to_roi_maps = ''; % Path to your ROIs maps, extracted by MarsBars or whatever software... Can be left empty if you want to setup them yourself. If filled, the folder is expected to contain one ROI per .nii file. Each filename will serve as the ROI name in CONN. This script only supports ROI for all subjects (not one ROI per subject, nor one ROI per session, but you can modify the script, these features are supported by CONN).
loading_mode = 0; % loading mode: raw files (0) or already preprocessed (1)? If 0 (raw files), the prefixes below won't be used, and you will need to run CONN Preprocessing before proceeding to analysis.

% -- Mode 1 parameters (already preprocessed dataset)
% These parameters will be used only if you set loading_mode = 1
func_smoothed_prefix = 's10wa'; % prefix of the functional images you want to use (generally the smoothed motion corrected functional images). Use: s8rwa for VBM8, s8wra for SPM12 OldSeg, s8wra for CAT12.
roiextract_type = 1; % extract ROI from what kind of functional images? 1: smoothed images (same files as for the rest of the analysis) ; 2: raw images by stripping the SPM smoothing prefix 's' ; 3: raw images by stripping the smoothing prefix specified above ; 4: other files (NOT SUPPORTED in this script yet). Why use 2 or 3? From CONN's manual, it is a standard good practice advised by CONN: smoothed data for voxel-level descriptions (because this increases the reliability of the resulting connectivity measures), but use if possible the non-smoothed data for ROI-level descriptions (because this decreases potential 'spillage' of the BOLD signal from nearby areas/ROIs). If empty, we will reuse the smoothed images for ROI-level descriptions.
struct_norm_prefix = 'wm[^i]'; % prefix for the (MNI) normalized structural image. Use: wmr for VBM8, wm for SPM12 OldSeg, wm (non-segmented) or wp0 (segmented) for CAT12.
struct_segmented_grey_prefix = 'wc1'; % prefix for segmented structural grey matter. Use: m0wrp1 for VBM8, wc1 for SPM12 OldSeg, wp1 (non-modulated) or mwp1 (modulated) for CAT12.
struct_segmented_white_prefix = 'wc2'; % idem for white matter. Use wc2 for SPM12 OldSeg.
struct_segmented_csf_prefix = 'wc3'; % idem for csf. Use wc3 for SPM12 OldSeg.
struct_additional_rois = struct(); % provide additional structural rois to regress out the noise from these rois signal, eg, lesions masks such as WMHC automatic segmentation in CAT12: struct('wmhc', '^wp7.*\.(img|nii)$');
nb_first_volumes_to_remove = 0; % NOT READY, DO NOT USE! % number of functional volumes to remove, to reduce the fMRI coil calibration bias at the start of the acquisition (ie, the fMRI scanner needs an exponentially decreasing time to calibrate at the beginning, generally 3-4 volumes). Set 0 to disable. NOTE: works only with multi-files nifti *.img/*.hdr (NOT with 4D nifti yet!).
firstlevelcovars = struct() % regular expressions to match .txt files in the same folder as the functional images and which will be used as 1st-level covariates. The fieldname is used as the covariate name, the value is the regex to match files. Eg, struct('movement', '^art_regression_outliers_and_movement_*.+)?\.mat$');

% -- Additional general parameters
automate = 0; % if 1, automate the processing (ie, launch the whole processing without showing the GUI until the end to show the results)
resume_job = 0; % resume from where the script was last stopped (ctrl-c or error). Warning: if you here change parameters of already done steps, they wont take effect! Only parameters of not already done steps will be accounted. Note that resume can also be used to add new subjects without reprocessing old ones.
run_dynamicfc = 0; % run Dynamic Functional Connectivity analysis? BEWARE: it may fail. This script tries to setup the experiment correctly so that DFC runs, but it may still fail for no obvious reason!
disable_conditions = 0; % do not configure conditions? (in case you have an error or if you want to configure yourself, conditions are tricky to configure)
save_denoised_fmri = 0; % to save denoised fmri (also called confound corrected bold timeseries), set this to 1 (this will take a lot of disk space and slow down analysis)
allow_missing_sessions = 0; % allow subjects to be missing sessions (eg, when studying sleep data, some subjects may be missing data in deep sleep stage N3, but not others, in this case if you want to use all subjects whether they have all sleep stages, you can set this to 1)
% ------ END OF PARAMETERS

% Notes and warnings
fprintf('Note: data is expected to be already preprocessed\n(realignment/slicetiming/coregistration/segmentation/normalization/smoothing)\n');
fprintf('Note2: this script expects a very specific directry tree layout\nfor your images (see script header comment). If not met,\nthis may produce errors like "Index exceeds matrix dimensions."\nwhen executing conn_batch(CONN_x).\n');
fprintf('Note3: if in inter-subjects mode you get the error\n"Reference to non-existent field t. Error in spm_hrf", you have to\nedit spm_hrf.m to replace stats.fmri.t by stats.fmri.fmri_t .\n');
fprintf('Note4: Voxel-to-Voxel analysis needs at least 2 subjects per group!\n');

% Temporarily restore factory path and set path to SPM and its toolboxes, this avoids conflicts when having different versions of SPM installed on the same machine
bakpath = path; % backup the current path variable
restoredefaultpath(); matlabpath(strrep(matlabpath, userpath, '')); % clean up the path
addpath_with_check(path_to_spm, 'spm'); % add the path to SPM
addpath_with_check(fullfile(path_to_spm, 'matlabbatch'), 'cfg_getfile'); % add the path to SPM matlabbatch (required by some versions of CONN...)
addpath_with_check(path_to_conn, 'conn'); % add the path to CONN toolbox

% Start logging if automating
if automate == 1
    % Alternative to diary: launch MATLAB with the -logfile switch
    logfile = [mfilename() '_' datestr(now, 'yyyy-mm-dd_HH-MM-ss') '.txt'];
    diary off;
    diary(logfile);
    diary on;
    finishup = onCleanup(@() stopDiary(logfile)); % need to use an onCleanup function to diary off and commit content into the logfile (could also use a try/catch block)
end

% START OF SCRIPT
fprintf('== Conn subjects loader ==\n');

% ------ LOADING SUBJECTS FILES
fprintf('-- Loading subjects files --\n');

% Scan the root path to extract all groups and subjects names
fprintf('Loading subjects groups...\n');
% Extract groups
groups = get_dirnames(root_path);
groups = groups(~strcmp(groups, 'JOBS')); % remove JOBS from the groups
% Extract subjects names from inside the groups
subjects = {};
for g=1:length(groups)
    subjects{g} = struct('names', []); % associate the subjects names for each group
    subjn = get_dirnames(fullfile(root_path, groups{g}));
    subjects{g}.names = subjn;
end

% Counting number of subjects
subjects_real_total = 0;
subjects_total = 0;
for g=1:length(groups)
    subjects_real_total = subjects_real_total + length(subjects{g}.names);
end
% count every subjects across all groups
subjects_total = subjects_real_total;

% Extracting all info and files for each subject necessary to construct the CONN project
% We first construct our own "data" struct with our own format, this is easier to manage
% Then later, we fill the CONN project using the info from this "data" struct
fprintf('Detect images for all subjects...\n');
data = struct('groups', []);
data.groups = struct('id', {}, 'subjects', {});
sid = 0;
for g=1:length(groups)
    data.groups{g}.id = groups{g};
    for s=1:length(subjects{g}.names)
        sid = sid + 1;
        % Initialize the subject's struct
        sname = subjects{g}.names{s};
        spath = fullfile(root_path, groups{g}, sname);
        data.groups{g}.subjects{s} = struct('id', sname, ...
                                                'dir', spath, ...
                                                'sessions', [] ...
                                                );
        % Find the sessions
        sessions = get_dirnames(fullfile(spath, 'data'));
        sessions = sessions(~strcmp(sessions, 'mprage')); % exclude mprage (shared structural folder)
        if length(sessions) == 0, sessions = {'.'}; end % hierarchy tolerance (ie, if folders do not exist at this level, just stay here and try to continue)

        for sessid=1:length(sessions)
            % Print status
            fprintf('Detect images for subject %i/%i session %i/%i (%s %s %s)...\n', sid, subjects_real_total, sessid, length(sessions), groups{g}, sname, sessions{sessid});

            % Get path to images (inside each session)
            datapath = fullfile(spath, 'data');
            sesspath = fullfile(datapath, sessions{sessid});

            % Init session data struct
            session = struct('id', sessions{sessid}, ...
                             'isstructshared', false, ...
                             'files', struct('struct', [], ...
                                             'func', [], ...
                                             'roi', [])); % Note: NEVER init with {}, always with [] because else the struct will be considered empty and unmodifiable! (famous errors: ??? A dot name structure assignment is illegal when the structure is empty. or ??? Error using ==> end)

            % Get full filepaths of all images
            structpath = getimgpath(sesspath, 'struct');
            isstructshared = false;
            if ~exist(structpath, 'dir')
                % If there is no per session structural image, get a shared image (shared across sessions)
                structpath = getimgpath(datapath, 'struct');
                isstructshared = true;
                if ~exist(structpath, 'dir')
                    error('Error: No structural mprage directory for subject %s.', sname);
                end
            end
            funcpath = getimgpath(sesspath, 'func'); % do not use the func_motion_corrected subdirectory to find smoothed func images, because we need both the smoothed motion corrected images AND the original images for CONN to work best
            funcmotpath = getimgpath(sesspath, 'func');

            % Load the structural images
            if loading_mode == 0
                session.files.struct = check_exist(regex_files(structpath, ['^.+\.(img|nii)$']));
            else
                session.files.struct = check_exist(regex_files(structpath, ['^' struct_norm_prefix '.+\.(img|nii)$']));
            end
            session.isstructshared = isstructshared;
            % Load functional motion artifacts corrected, realigned, smoothed images
            if loading_mode == 0
                session.files.func = check_exist(regex_files(funcpath, ['^.+\.(img|nii)$']));
            else
                session.files.func = check_exist(regex_files(funcpath, ['^' func_smoothed_prefix '.+\.(img|nii)$']));
            end

            if loading_mode == 1
                % Load regions of interests (we expect 3 different ROIs: 1,2,3 respectively for grey matter, white matter and CSF)
                session.files.roi = struct('grey', [], 'white', [], 'csf', []);
                session.files.roi.grey = check_exist(regex_files(structpath, ['^' struct_segmented_grey_prefix '.+\.(img|nii)$']));
                session.files.roi.white = check_exist(regex_files(structpath, ['^' struct_segmented_white_prefix '.+\.(img|nii)$']));
                session.files.roi.csf = check_exist(regex_files(structpath, ['^' struct_segmented_csf_prefix '.+\.(img|nii)$']));
                if numel(fieldnames(struct_additional_rois)) > 0
                    % Load additional structural rois to regress (such as lesion maps)
                    roikeys = fieldnames(struct_additional_rois);
                    for ri=1:numel(roikeys)
                        rkey = roikeys{ri};
                        rreg = getfield(struct_additional_rois, rkey);
                        session.files.roi.(rkey) =  check_exist(regex_files(structpath, rreg));
                    end %endfor
                end
            end

            % 1st-level covariates
            if loading_mode == 1 && numel(fieldnames(firstlevelcovars)) == 0
                % By default in mode 1, load movement covariates (retrocompatibility)
                % ART movement artifacts correction
                firstlevelcovars = struct('movement', '^art_regression_outliers_and_movement_*.+)?\.mat$');
            end
            if numel(fieldnames(firstlevelcovars)) > 0
                % Load all first level covariates
                flckeys = fieldnames(firstlevelcovars);
                for fidx=1:numel(flckeys)
                    fkey = flckeys{fidx};
                    freg = getfield(firstlevelcovars, fkey);
                    session.files.covars1.(fkey) =  check_exist(regex_files(funcmotpath, freg));
                end %endfor
            end

            % Remove first x functional volumes (to avoid fMRI coil gradient calibration bias)
            if nb_first_volumes_to_remove > 0
                session.files.func = session.files.func(nb_first_volumes_to_remove+1:end);
            end
            % Append in the list of sessions for this subject in our big data struct
            data.groups{g}.subjects{s}.sessions{end+1} = session;
        end % for sessions
    end % for subjects
end % for groups

% ROIs detection
if length(path_to_roi_maps) > 0
    fprintf('ROIs maps detection...\n');
    % Get all the roi files
    roi_maps = regex_files(path_to_roi_maps, '^.+\.(nii|img)$');  % can also provide .hdr, but if it's a multi-rois image, then it won't be detected automatically. For automatic multi-rois detection in CONN, provide the .img instead of .hdr.
    % Extract the filenames, they will serve as the roi names in CONN
    roi_names = {};
    for r=1:length(roi_maps)
        [~, n] = fileparts(roi_maps{r});
        roi_names{r} = n;
    end
end

% Sanity checks
fprintf('Sanity checks...\n');
% 1. Check globally that there are any loaded images, else the tree structure is obviously wrong
if isempty(data.groups(:)); error('Cannot find any subject group! Please check your dataset directories structure, it should be: <group>/<subject>/data/<session>/(mprage|rest)/*.(img|nii)'); end;
check_cond = data.groups{:};
if isempty(check_cond.subjects(:)); error('Cannot find any subject! Please check your dataset directories structure.'); end;
check_subj = check_cond.subjects{:}; % MATLAB does not support chaining {:} (eg, a{:}.b{:}) so we need to split this command on several lines...
if isempty(check_subj.sessions(:)); error('Cannot find any session! Please check your dataset directories structure.'); end;
check_sess = check_subj.sessions{:};
if length(check_sess.files.struct) == 0
    error('No structural image found. Please check that the specified root_path follows the required tree structure.');
end
if length(check_sess.files.func) == 0
    error('No functional image found. Please check that the specified root_path follows the required tree structure.');
end

% 2. Check for each group, subject and session that there are both structural and functional images
for g=1:length(data.groups)
    if ~isfield(data.groups{g}, 'subjects') || isempty(data.groups{g}.subjects); error('No subjects for group %s. Please check your dataset structure.', data.groups{g}.id); end;
    for s=1:length(data.groups{g}.subjects)
        if ~isfield(data.groups{g}.subjects{s}, 'sessions') || isempty(data.groups{g}.subjects{s}.sessions); error('No sessions for group %s subject %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id); end;
        for sessid=1:length(data.groups{g}.subjects{s}.sessions)
            subjfile = data.groups{g}.subjects{s}.sessions{sessid}.files;
            if isempty(subjfile.struct); error('No structural image found for group %s subject %s session %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id); end;
            if iscell(subjfile.struct) && (numel(subjfile.struct) > 1); error('Multiple structural image found for group %s subject %s session %s. Need only one structural per subject and session. Please check your dataset structure. Here is the list:\n%s', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id, subjfile.struct{:}); end;
            if isempty(subjfile.func); error('No functional image found for group %s subject %s session %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id); end;
            if loading_mode == 1
                if isempty(subjfile.roi.grey); error('No segmented grey matter image found for group %s subject %s session %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id); end;
                if isempty(subjfile.roi.white); error('No segmented white matter image found for group %s subject %s session %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id); end;
                if isempty(subjfile.roi.csf); error('No segmented csf matter image found for group %s subject %s session %s. Please check your dataset structure.', data.groups{g}.id, data.groups{g}.subjects{s}.id, data.groups{g}.subjects{s}.sessions{sessid}.id); end;
            end
        end % end for sessions
    end % end for subjects
end % end for groups

% 3. Check if the number of sessions is consistent for all subjects (the number of sessions can be different per subject but it's good to notify the user in case this is a mistake)
count_sessions = length(data.groups{1}.subjects{1}.sessions);
for g=1:length(groups)
    for s=1:length(subjects{g}.names)
        if count_sessions ~= length(data.groups{g}.subjects{s}.sessions)
            fprintf('Warning: Different number of sessions between subjects, please check them! group %s subject %s has %i sessions, group %s subject %s has %i sessions.\n', groups{1}, subjects{1}.names{1}, length(data.groups{1}.subjects{1}.sessions), groups{g}, subjects{g}.names{s}, length(data.groups{g}.subjects{s}.sessions));
        end
    end
end


% ---- CONSTRUCTING AND FILLING CONN PROJECT STRUCT
% This is where we build the CONN batch project and load in it all the infos we gathered before
fprintf('-- Generating CONN project struct --\n');
fprintf('Struct initialization...\n');
clear CONN_x;
CONN_x = {};

% load the structure and modify it
%clear CONN_x;
%load(conn_file);

% SETUP
CONN_x.filename = conn_file; % Our new conn_*.mat project filename
CONN_x.Setup.isnew = 1;  % tell CONN that this is a new project we will completely programmatically define without using a SPM.mat, and thus CONN should fill this struct with the default project structure (ie, add all the required fields)
if resume_job == 1, CONN_x.Setup.isnew = 0; end;
CONN_x.Setup.done = 0;  % do not execute any task, just fill the fields
CONN_x.Setup.nsubjects = subjects_total;
if isscalar(TR)
    CONN_x.Setup.RT = ones(1, subjects_total) * TR;
else
    CONN_x.Setup.RT = TR;
end %endif
CONN_x.Setup.acquisitiontype = 1; % continuous
CONN_x.Setup.analyses=1:4; % set the type of analyses to run (basically: all)
CONN_x.Setup.voxelresolution = 1; % set voxel resolution to the default, normalized template (or set 2 for same as structurals, 3 for same as functionals, or 4 for same as freesurfer for surface-based analysis)
CONN_x.Setup.analysisunits = 1; % set BOLD signal units to percent signal change
CONN_x.Setup.outputfiles = [1 0 1 1 1 1]; % save additional output files by default (except denoised fmri / confound corrected bold timeseries, as these ones take a lot of space and more processing time)
if save_denoised_fmri == 1, CONN_x.Setup.outputfiles(2) = 1; end;

% OTHER PARTS -> DISABLE
CONN_x.Denoising.done = 0;
CONN_x.Analysis.done = 0;
CONN_x.Results.done = 0;

% LOADING IMAGES
fprintf('Loading images...\n');
% Initializing required fields
CONN_x.Setup.structurals = {};
CONN_x.Setup.functionals = {};
CONN_x.Setup.masks.Grey = {};
CONN_x.Setup.masks.White = {};
CONN_x.Setup.masks.CSF = {};
% Main filling loop
% We transfer everything we detected to a new batch struct with the structure expected by conn_batch (this is sort of a struct translation/conversion call it whatever you want)
sid = 0; % subject counter, because we need to add them all in a row in CONN, we assign groups later
for g=1:length(groups)
    for s=1:length(subjects{g}.names)
        sid = sid + 1; % We need to continue the subjects counter after switch to next group, but subject counter s will go back to 0, hence the sid which is the CONN subject's id
        sessions = data.groups{g}.subjects{s}.sessions;
        for sessid=1:length(data.groups{g}.subjects{s}.sessions)
            % Init structural and functional images cell
            if length(CONN_x.Setup.structurals) < sid % extend and init if adding a new subject
                CONN_x.Setup.structurals{sid} = {};
                CONN_x.Setup.functionals{sid} = {};
            end
            % Add structural images
            if sessions{sessid}.isstructshared
                % Structural image is shared across sessions
                CONN_x.Setup.structurals{sid} = sessions{sessid}.files.struct;
            else
                % One struct image per session
                CONN_x.Setup.structurals{sid}{sessid} = sessions{sessid}.files.struct;
            end
            % Add functional images
            CONN_x.Setup.functionals{sid}{sessid} = char(sessions{sessid}.files.func); % convert cell array to char array for CONN
            % Preprocessed files loading (when loading_mode == 1)
            if loading_mode == 1
                % ROI masks (= segmented grey/white/csf images)
                CONN_x.Setup.masks.Grey{sid}{sessid} = sessions{sessid}.files.roi.grey;
                CONN_x.Setup.masks.White{sid}{sessid} = sessions{sessid}.files.roi.white;
                CONN_x.Setup.masks.CSF{sid}{sessid} = sessions{sessid}.files.roi.csf;
            end
            % Additional ROIs (such as lesions masks)
            if numel(fieldnames(struct_additional_rois)) > 0
                roikeys = fieldnames(struct_additional_rois);
                for ri=1:numel(roikeys)
                    CONN_x.Setup.rois.files{ri}{sid}{sessid} = sessions{sessid}.files.roi.(roikeys{ri});
                end
            end
            % Covariates 1st-level
            if numel(fieldnames(firstlevelcovars)) > 0
                flckeys = fieldnames(firstlevelcovars);
                for fidx=1:numel(flckeys)
                    CONN_x.Setup.covariates.files{fidx}{sid}{sessid} = sessions{sessid}.files.covars1.(flckeys{fidx});
                end
            end
        end % for sessions
    end % for subjects
end % for groups

% SUBJECTS GROUPS
fprintf('Loading groups...\n');
CONN_x.Setup.subjects.group_names = groups;
CONN_x.Setup.subjects.groups = [];
for g=1:length(groups)
    CONN_x.Setup.subjects.groups = [CONN_x.Setup.subjects.groups ones(1, length(subjects{g}.names))*g];
end
if conn_ver < 17
    % CONN equal or below version 16 required a covariate "AllSubjects" and a condition "AllSessions" to allow Dynamic Functional Connectivity analysis analysis
    CONN_x.Setup.subjects.effect_names = {'AllSubjects'};
    CONN_x.Setup.subjects.effects{1} = ones(1, subjects_total);
end

% CONDITIONS DURATION
% Here, we want to look at the difference between the sessions (pre-post kind of experiment), so the different conditions are considered to be the difference between the sessions, so the conditions are the same as the sessions
if disable_conditions == 0
    % Count maximum number of sessions
    max_count_sessions = 0;
    for g=1:length(groups), for s=1:length(subjects{g}.names)
        nb_sess = length(data.groups{g}.subjects{s}.sessions);
        if nb_sess > max_count_sessions
            max_count_sessions = nb_sess;
        end
    end; end

    % Set as many conditions as there are sessions (because each condition is each session)
    nsessions = max_count_sessions;
    nconditions = nsessions;
    % Create conditions names (just 'session_x')
    vec2str = @(v) strtrim(cellstr(num2str(v')));
    CONN_x.Setup.conditions.names = strcat('session_', vec2str(1:nsessions))';
    % Set whether missing sessions are to be expected
    CONN_x.Setup.conditions.missingdata = allow_missing_sessions;
    % For each subject and subject/session
    for ncond=1:nconditions,for nsub=1:subjects_total,for nses=1:length(CONN_x.Setup.functionals{nsub})
        % Assign if session == condition and the session exists for this subject, else set to empty
        if ncond == nses && length(CONN_x.Setup.functionals{nsub}) >= nses % note: the second condition is just a sanity check, not necessary because we already loop only for sessions that exist for this subject
            CONN_x.Setup.conditions.onsets{ncond}{nsub}{nses} = 0;
            CONN_x.Setup.conditions.durations{ncond}{nsub}{nses} = inf;
        else
            CONN_x.Setup.conditions.onsets{ncond}{nsub}{nses} = [];
            CONN_x.Setup.conditions.durations{ncond}{nsub}{nses} = [];
        end
    end;end;end     % rest condition (all sessions)
    if conn_ver < 17
        % CONN equal or below version 16 required a covariate "AllSubjects" and a condition "AllSessions" to allow Dynamic Functional Connectivity analysis
        CONN_x.Setup.conditions.names = [CONN_x.Setup.conditions.names {'AllSessions'}];
        for ncond=nconditions+1,for nsub=1:subjects_total,for nses=1:length(CONN_x.Setup.functionals{nsub})
            CONN_x.Setup.conditions.onsets{ncond}{nsub}{nses}=0;
            CONN_x.Setup.conditions.durations{ncond}{nsub}{nses}=inf;
        end;end;end     % rest condition (all sessions)
    end
end

% COVARIATES LEVEL-1: intra-subject covariates: artifacts we will regress (remove)
if loading_mode == 1
    CONN_x.Setup.covariates.names = fieldnames(firstlevelcovars);
    CONN_x.Setup.covariates.add = 0;
end

% ROIS CONFIGURATION
%start_rois = length(CONN_x.Setup.rois.names);
CONN_x.Setup.rois.add = 0; % Add over the existing ROIs

% Configure additional structural roi regressors (eg, lesions maps)
roikeys = fieldnames(struct_additional_rois);
for ri=1:length(roikeys)
    CONN_x.Setup.rois.names{ri} = roikeys{ri};
    CONN_x.Setup.rois.dimensions{ri} = 16; % use PCA decomposition (just like GM/WM/CSF rois, with the default number of components for the PCA decomposition
    CONN_x.Setup.rois.weighted(ri) = 0; % non weighted
    CONN_x.Setup.rois.regresscovariates(ri) = 1;
end %endfor

% Load and configure real ROIs maps (ie, seeds, atlases)
if length(path_to_roi_maps) > 0
    count_struct_rois = numel(fieldnames(struct_additional_rois));
    for r=1:length(roi_names)
        r2 = r + count_struct_rois;
        CONN_x.Setup.rois.names{r2} = roi_names{r};
        CONN_x.Setup.rois.files{r2} = roi_maps{r};
        CONN_x.Setup.rois.dimensions{r2} = 1; % use extracted timeseries (no PCA decomposition)
        CONN_x.Setup.rois.weighted(r2) = 0; % non weighted
        CONN_x.Setup.rois.regresscovariates(r2) = 0;
    end %endfor
end

% ROI-level BOLD timeseries extraction: reuse smoothed functional images or use raw images?
% See for more info: http://www.nitrc.org/forum/forum.php?thread_id=4515&forum_id=1144
if roiextract_type ~= 3
    CONN_x.Setup.roifunctionals.roiextract = roiextract_type;
elseif roiextract_type == 3 && ~isempty(func_smoothed_prefix)
    CONN_x.Setup.roifunctionals.roiextract = 3;
    CONN_x.Setup.roifunctionals.roiextract_rule = {};
    CONN_x.Setup.roifunctionals.roiextract_rule{1} = 1; % work on filename, not on absolute path
    CONN_x.Setup.roifunctionals.roiextract_rule{2} = ['^' func_smoothed_prefix];
    CONN_x.Setup.roifunctionals.roiextract_rule{3} = '';
end

% DENOISING
%CONN_x.Denoising.confounds.names = [{'Grey Matter', 'White Matter', 'CSF'}, CONN_x.Setup.rois.names]; % use GM/WM/CSF + all rois as denoising confounds effects

% ANALYSIS
CONN_x.Analysis.type = 3; % do all analyses at once, we will explore and choose them later
% ROI-to-ROI and Seed-to-Voxel
if length(path_to_roi_maps) > 0 % avoid a NaN bug during analysis if no ROI is provided
    CONN_x.Analysis.sources = CONN_x.Setup.rois.names; % Use all ROIs
end
% Voxel-to-voxel
% Note that conn_batch cannot do all 1st-level analyses, if you specify Analysis.measures then it will compute only Voxel-to-Voxel analysis, else only ROI-to-ROI/Seed-to-Voxel analysis (but we workaround that by calling conn_process directly for the other analyses, see below)
if conn_ver < 17
    CONN_x.Analysis.measures = conn_v2v('measurenames'); % Load all available kinds of measures
elseif conn_ver >= 17
    CONN_x.vvAnalysis.measures = conn_v2v('measurenames'); % Load all available kinds of measures
end

% Automate processing?
if automate
    CONN_x.Setup.done = 1;
    CONN_x.Denoising.done = 1;
    CONN_x.Analysis.done = 1;
    CONN_x.Results.done = 1;
    if conn_ver >= 17
        CONN_x.vvAnalysis.done = 1;
        if run_dynamicfc; CONN_x.dynAnalysis.done = 1; else; CONN_x.dynAnalysis.done = 0; end;
        CONN_x.vvResults.done = 1;
    end
end

% Resume?
if resume_job
    CONN_x.Setup.overwrite = 0;
    CONN_x.Denoising.overwrite = 0;
    CONN_x.Analysis.overwrite = 0;
    % Always recompute the 2nd level results based on first level
    CONN_x.Results.overwrite = 1;
    if conn_ver >= 17
        CONN_x.vvAnalysis.overwrite = 0;
        CONN_x.dynAnalysis.overwrite = 0;
        CONN_x.vvResults.overwrite = 1;
    end
end

% ---- SAVE/LOAD INTO CONN
if automate == 0
    fprintf('-- Save/load into CONN --\n');
    fprintf('Save project via conn_batch (may take a few minutes)...\n');
elseif automate == 1
    fprintf('-- Save into CONN and run batch --\n');
    fprintf('Save and run project via conn_batch (may take a while for the whole analysis to finish)...\n');
end
% EXECUTE BATCH (to convert our raw CONN_x struct into a project file - because the structure is a bit different with the final CONN_x (eg, CONN_x.Setup.structural instead of CONN_x.Setup.structurals with an 's' at the end, plus the structure inside is different)
% Save our CONN_x structure onto a project file using conn_batch() to do the conversion and fill missing fields
% If automate = 1, we also run the experiments, so the project file will also contain the results
conn_batch(CONN_x); % if you get an error, your CONN_x struct is malformed (maybe some files are missing, or project type is incorrect?)
%save(conn_file, 'CONN_x');  % DEPRECATED: saving directly into a mat file does not work because conn_batch will reprocess CONN_x into the internal format, which is different to conn_batch API.

% PROCESS OTHER 1ST-LEVEL ANALYSES
% conn_batch can only do one type of analysis at a time. Here we workaround by directly calling conn_process for each missed analysis.
if automate
    % First: load the CONN_x batch struct, conn_process will access it as a global
    clear CONN_x;
    load(conn_file); % will load var CONN_x into workspace
    global CONN_x;
    CONN_x.gui.overwrite = 'Yes' % avoid CONN GUI asking us what to do, overwrite files directly
    % Compute Seed-to-Voxel 1st-level analysis
    conn_process('analyses_seed');
    % Compute ROI-to-ROI 1st-level analysis
    conn_process('analyses_seedandroi');
    % Compute Dynamic FC (functional connectivity) 1st-level analysis
    % Trick to compute DFC is to use the backprojection technic: you need to create a condition and a 2nd-level group that includes all subjects across all conditions/sessions.
    if run_dynamicfc == 1, conn_process('analyses_dyn'); end;
    % Save the new struct and results!
    if isfield(CONN_x,'filename'), conn save; end;
end

% LOAD/DISPLAY EXPERIMENT FILE INTO CONN GUI
fprintf('Load project into CONN GUI...\n');
% Clear up a bit of memory
clear CONN_x data;
% Launch conn gui to explore results
conn;  % launch CONN
conn('load', conn_file);  % Load the parameters/results
if automate == 0
    conn gui_setup; % Refresh display: need to refresh the gui to show the loaded parameters. You can also directly switch to any other panel: gui_setup, gui_results, etc.
elseif automate == 1
    conn gui_results; % Refresh display and switch directly to the results tab.
end

% THE END
fprintf('Done!\n');
fprintf('Tip: when you hover the mouse cursor over an image, a title with the file path appears. You can hover the cursor on it to get the full path, or double click on it to show the file on the right panel.\n');
fprintf('Press Enter to restore path and exit...\n');
input('','s');
path(bakpath); % restore the path to the previous state
if automate == 1, diary off; end;
end  % endfunction

% =========================================================================
%                              Auxiliary Functions
% =========================================================================

function dirNames = get_dirnames(dirpath)
% dirNames = get_dirnames(dirpath)
% Get the list of subdirectories inside a directory

    % Get a list of all files and folders in this folder.
    files = dir(dirpath);
    % Extract only those that are directories.
    subFolders = files([files.isdir]);
    dirNames = {subFolders.name};
    dirNames = dirNames(3:end); % remove '.' and '..'
end

function fpath = getimgpath(dirpath, imtype)
% fpath = get_images_path(dirpath, imtype)
% Generate directory paths according to Cyclotron standard tree layout
% This eases access to the various images types

    fpath = '';
    switch imtype
        case 'struct'  % anatomical images (T1 aka structural) folder
            fpath = fullfile(dirpath, 'mprage', 'mri');  % compatibility with CAT12
            if ~(exist(fpath, 'dir') == 7)
                fpath = fullfile(dirpath, 'mprage');
            end
        case 'func' % functional images (T2) folder
            fpath = fullfile(dirpath, 'rest');
            if ~exist(fpath, 'dir')
                fpath = fullfile(dirpath, 'func');
            end
        case 'func_motion_corrected'
            fpath = fullfile(dirpath, 'rest', 'restMotionCorrected');
            if ~exist(fpath, 'dir')
                fpath = fullfile(dirpath, 'func', 'restMotionCorrected');
            end
    end
end

function filesList = regex_files(dirpath, regex)
% filesList = regex_files(dirpath, regex)
% Extract files from a directory using regular expression

    % Get all files in directory
    filesList = dir(dirpath);
    % Filter out directories
    filesList = filesList(~[filesList.isdir]);
    % Use regular expression to filter only the files we want
    filesList = regexp({filesList.name}, regex, 'match');
    % Concatenate the filenames in a cellarray
    %filesList = {filesList.name};
    % Remove empty matches
    filesList = [filesList{:}];
    % Prepend the full path before each filename (so that we get absolute paths)
    if length(filesList) > 0
        filesList = cellfun(@(f) fullfile(dirpath, f), filesList, 'UniformOutput', false);
    end
    % Return directly the string instead of the cell array if there is only one file matched
    if length(filesList) == 1
        filesList = filesList{1};
    end
end

function filelist = check_exist(filelist)
%check_exist  Check if all the files in a given filelist exist, if not, print a warning
    if strcmp(class(filelist), 'cell')
        files_count = numel(filelist);
    else
        files_count = size(filelist, 1);
    end

    if isempty(filelist)
        msgID = 'check_exist:FileNotFound';
        msg = 'Error: file not found (filepath is empty).';
        FileNotFoundException = MException(msgID,msg);
        throw(FileNotFoundException);
    end
    for fi = 1:files_count
        if class(filelist) == 'cell'
            f = filelist{fi};
        else
            f = filelist(fi, 1:end);
        end
        if ~(exist(f, 'file') == 2) || isempty(f)
            msgID = 'check_exist:FileNotFound';
            msg = sprintf('Error: file not found: %s\nPlease check if the file exists, or if the path is too long (try to shorten parent folders names).\n', f);
            FileNotFoundException = MException(msgID,msg);
            throw(FileNotFoundException);
        end
    end % endfor
end

function err_report = getReportError(errorStruct)
%getReportError  Get error report from specified error or lasterror (similarly to getReport() with exceptions)

    % Get last error if none specified
    if nargin == 0
        errorStruct = lasterror;
    end

    % Init
    err_report = '';

    % Get error message first
    if ~isempty(errorStruct.message)
        err_report = errorStruct.message;
    end

    % Then get error stack traceback
    errorStack = errorStruct.stack;
    for k=1:length(errorStack)
        stackline = sprintf('=> Error in ==> %s at %d', errorStack(k).name, errorStack(k).line);
        err_report = [err_report '\n' stackline];
    end
end

function stopDiary(logfile)
% Stop diary to save it into the logfile and save last error
% to be used with onCleanup, to commit the diary content into the log file
    % Stop the diary (commit all that was registered to the diary file)
    diary off;
    % Get the last error if there's one
    err = lasterror();
    if length(err.message) > 0
        errmsg = getReportError(err);
        fid = fopen(logfile, 'a+');
        fprintf(fid, ['ERROR: ??? ' errmsg]);
        fclose(fid);
    end
end

function addpath_with_check(apath, cmd2check)
% add_path_with_check(apath, cmd2check)
% Add a path to Matlab's PATH, and check if the path is correct by calling a command to check
    addpath(apath);
    check = which(cmd2check, '-ALL');
    if length(check) == 0
        error('Addpath failed for command "%s": incorrect path: %s\n', cmd2check, apath);
    elseif length(check) > 1
        error('Addpath failed for command "%s": too many paths, there should be only one (please restoredefaultpath()): %s\n', cmd2check, sprintf('%s, ', check{:}));
    end
end
