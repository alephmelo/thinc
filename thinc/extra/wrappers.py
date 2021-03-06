import contextlib
from ..compat import BytesIO
from ..neural._classes.model import Model

try:
    import torch.autograd
    import torch.optim
    import torch
except ImportError:
    pass


class PyTorchWrapper(Model):
    '''Wrap a PyTorch model, so that it has the same API as Thinc models.
    To optimize the model, you'll need to create a PyTorch optimizer and call
    optimizer.step() after each batch --- see examples/wrap_pytorch.py
    '''
    def __init__(self, model):
        Model.__init__(self)
        self._model = model
        self._optimizer = None

    def begin_update(self, x_data, drop=0.):
        '''Return the output of the wrapped PyTorch model for the given input,
        along with a callback to handle the backward pass.
        '''
        x_var = torch.autograd.Variable(torch.Tensor(x_data),
                                        requires_grad=True)
        # Make prediction
        y_var = self._model(x_var)
        def backward_pytorch(dy_data, sgd=None):
            dy_var = torch.autograd.Variable(torch.Tensor(dy_data))
            torch.autograd.backward((y_var,), grad_variables=(dy_var,))
            dX = self.ops.asarray(x_var.grad.data)
            if sgd is not None:
                if self._optimizer is None:
                    self._optimizer = self._create_optimizer(sgd)
                self._optimizer.step()
                self._optimizer.zero_grad()
            return dX
        return self.ops.asarray(y_var.data), backward_pytorch

    def _create_optimizer(self, sgd):
        params = self._model.parameters()
        if sgd.b1 != 0 and sgd.b2 != 0:
            optimizer = torch.optim.Adam(params, lr=sgd.alpha, betas=(sgd.b1, sgd.b2))
        elif sgd.b2 == 0:
            optimizer = torch.optim.SGD(params, lr=sgd.alpha, momentum=sgd.b1)
        else:
            raise NotImplementedError
        return optimizer

    def to_disk(self, path):
        # TODO: Untested
        torch.save(self._model.state_dict(), str(path))

    def from_disk(self, path):
        # TODO: Untested
        self._model.load_state_dict(torch.load(path))

    def to_bytes(self):
        # TODO: Untested
        filelike = BytesIO()
        torch.save(self._model.state_dict(), filelike)
        return filelike.read()

    def from_bytes(self, data):
        # TODO: Untested
        filelike = BytesIO(data)
        self._model.load_state_dict(torch.load(filelike))

    def to_gpu(self, device_num):
        self._model.cuda(device_num)

    def to_cpu(self):
        self._model.cpu()

    def resize_output(self, new_dim):
        #self.weight = nn.Parameter(F.pad(self.weight, ...)) # add classes
        #self.weight = nn.Parameter(F.pad(model.weight, ...)) # add classes
        raise NotImplementedError

    def resize_input(self):
        raise NotImplementedError

    @contextlib.contextmanager
    def use_params(self, params): # pragma: no cover
        if self.id in params:
            backup = self.to_bytes()
            self.from_bytes(params[self.id])
        else:
            backup = None
        yield
        self.from_bytes(backup)

