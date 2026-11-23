import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from './serviceDeskIntake';

const operationId = '87ad2d68-2d49-4b9e-a981-98ed1de3a236';
const scope = { account_id: '3', user_id: '7', operation_id: operationId };
const requests = { post: vi.fn(), get: vi.fn() };

describe('Service Desk intake operations', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal('axios', requests);
    requests.post.mockResolvedValue({ data: { ...scope, state: 'queued' } });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('waits beyond the old readiness timeout without repeating the POST', async () => {
    requests.get.mockResolvedValue({ data: { ...scope, state: 'queued' } });
    const signal = new AbortController().signal;
    const result = API.preview('3', { inbox_id: '13' }, signal);
    await vi.advanceTimersByTimeAsync(432000);
    requests.get.mockResolvedValue({
      data: { ...scope, state: 'completed', result: { ready: true } },
    });
    await vi.advanceTimersByTimeAsync(3000);
    await expect(result).resolves.toEqual({
      data: { account_id: '3', user_id: '7', ready: true },
    });
    expect(requests.post).toHaveBeenCalledTimes(1);
    expect(requests.get).toHaveBeenCalledWith(
      `/api/v1/accounts/3/jrc_service_desk/intake/operations/${operationId}`,
      { signal, timeout: 15000 }
    );
  });

  it('rejects a response from another account', async () => {
    requests.get.mockResolvedValue({
      data: { ...scope, account_id: '9', state: 'completed', result: {} },
    });
    const result = API.publish(
      '3',
      { inbox_id: '13' },
      new AbortController().signal
    );
    const rejected = expect(result).rejects.toThrow('Stale scope');
    await vi.advanceTimersByTimeAsync(3000);
    await rejected;
  });

  it('stops polling after leaving the configuration', async () => {
    const controller = new AbortController();
    const result = API.preview('3', { inbox_id: '13' }, controller.signal);
    const rejected = expect(result).rejects.toMatchObject({
      name: 'AbortError',
    });
    await vi.advanceTimersByTimeAsync(1000);
    controller.abort();
    await rejected;
    await vi.advanceTimersByTimeAsync(4000);
    expect(requests.get).not.toHaveBeenCalled();
  });
});
