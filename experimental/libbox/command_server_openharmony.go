//go:build openharmony

package libbox

import "context"

func NewCommandServerWithContext(ctx context.Context, handler CommandServerHandler, platformInterface PlatformInterface) (*CommandServer, error) {
	return newCommandServer(ctx, handler, platformInterface)
}
