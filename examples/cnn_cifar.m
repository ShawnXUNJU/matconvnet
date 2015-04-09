function [net, info] = cnn_cifar(varargin)
% CNN_CIFAR   Demonstrates MatConvNet on CIFAR

run(fullfile(fileparts(mfilename('fullpath')), ...
  '..', 'matlab', 'vl_setupnn.m')) ;

opts.dataDir = fullfile('data','cifar') ;
opts.expDir = fullfile('data','cifar-baseline') ;
opts.imdbPath = fullfile(opts.expDir, 'imdb.mat');
opts.train.batchSize = 100 ;
opts.train.numEpochs = 20 ;
opts.train.continue = true ;
opts.train.gpus = [] ;
opts.train.learningRate = [0.001*ones(1, 12) 0.0001*ones(1,6) 0.00001] ;
opts.train.expDir = opts.expDir ;
opts = vl_argparse(opts, varargin) ;

% --------------------------------------------------------------------
%                                                         Prepare data
% --------------------------------------------------------------------

if exist(opts.imdbPath, 'file')
  imdb = load(opts.imdbPath) ;
else
  imdb = getCifarImdb(opts) ;
  mkdir(opts.expDir) ;
  save(opts.imdbPath, '-struct', 'imdb') ;
end

% Define network CIFAR10-quick
net.layers = {} ;

% Block 1
net.layers{end+1} = struct('type', 'conv', ...
                           'weights', {{1e-4*randn(5,5,3,32, 'single'), zeros(1, 32, 'single')}}, ...
                           'learningRate', [1 2], ...
                           'stride', 1, ...
                           'pad', 2) ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', [0 1 0 1]) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 2
net.layers{end+1} = struct('type', 'conv', ...
                           'weights', {{0.01*randn(5,5,32,32, 'single'), zeros(1,32,'single')}}, ...
                           'learningRate', [1 2], ...
                           'stride', 1, ...
                           'pad', 2) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'avg', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', [0 1 0 1]) ; % Emulate caffe

% Block 3
net.layers{end+1} = struct('type', 'conv', ...
                           'weights', {{0.01*randn(5,5,32,64, 'single'), zeros(1,64,'single')}}, ...
                           'learningRate', [1 2], ...
                           'stride', 1, ...
                           'pad', 2) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'avg', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', [0 1 0 1]) ; % Emulate caffe

% Block 4
net.layers{end+1} = struct('type', 'conv', ...
                           'weights', {{0.1*randn(4,4,64,64, 'single'), zeros(1,64,'single')}}, ...
                           'learningRate', [1 2], ...
                           'stride', 1, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 5
net.layers{end+1} = struct('type', 'conv', ...
                           'weights', {{0.1*randn(1,1,64,10, 'single'), zeros(1,10,'single')}}, ...
                           'learningRate', [1 2], ...
                           'stride', 1, ...
                           'pad', 0) ;

% Loss layer
net.layers{end+1} = struct('type', 'softmaxloss') ;

% --------------------------------------------------------------------
%                                                                Train
% --------------------------------------------------------------------

% Take the mean out and make GPU if needed
if numel(opts.train.gpus) == 1
  imdb.images.data = gpuArray(imdb.images.data) ;
end

[net, info] = cnn_train(net, imdb, @getBatch, ...
    opts.train, ...
    'val', find(imdb.images.set == 3)) ;

% --------------------------------------------------------------------
function [im, labels] = getBatch(imdb, batch)
% --------------------------------------------------------------------
im = imdb.images.data(:,:,:,batch) ;
labels = imdb.images.labels(1,batch) ;

% --------------------------------------------------------------------
function imdb = getCifarImdb(opts)
% --------------------------------------------------------------------
% Preapre the imdb structure, returns image data with mean image subtracted
unpackPath = fullfile(opts.dataDir, 'cifar-10-batches-mat');
files = [arrayfun(@(n) sprintf('data_batch_%d.mat', n), 1:5, 'UniformOutput', false) ...
  {'test_batch.mat'}];
files = cellfun(@(fn) fullfile(unpackPath, fn), files, 'UniformOutput', false);
file_set = uint8([ones(1, 5), 3]);

if any(cellfun(@(fn) ~exist(fn, 'file'), files))
  url = 'http://www.cs.toronto.edu/~kriz/cifar-10-matlab.tar.gz' ;
  fprintf('downloading %s\n', url) ;
  untar(url, opts.dataDir) ;
end

data = cell(1, numel(files));
labels = cell(1, numel(files));
sets = cell(1, numel(files));
for fi = 1:numel(files)
  fd = load(files{fi}) ;
  data{fi} = permute(reshape(fd.data',32,32,3,[]),[2 1 3 4]) ;
  labels{fi} = fd.labels' + 1; % Index from 1
  sets{fi} = repmat(file_set(fi), size(labels{fi}));
end

set = cat(2, sets{:});
data = single(cat(4, data{:}));
dataMean = mean(data(:,:,:,set == 1), 4);
data = bsxfun(@minus, data, dataMean);

clNames = load(fullfile(unpackPath, 'batches.meta.mat'));

imdb.images.data = data ;
imdb.images.data_mean = dataMean;
imdb.images.labels = single(cat(2, labels{:})) ;
imdb.images.set = set;
imdb.meta.sets = {'train', 'val', 'test'} ;
imdb.meta.classes = clNames.label_names;
