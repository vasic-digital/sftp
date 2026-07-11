// Package containers wraps the vasic-digital/containers submodule for the
// SFTP Enterprise project, fulfilling §11.4.76 ("the containers submodule
// MUST be used as the sole container orchestration layer — no ad-hoc
// docker/podman commands outside pkg/boot/pkg/compose/pkg/health").
//
// The Stack type boots and tears down the SFTP compose stack
// (deploy/docker-compose.yml) through the containers submodule's
// ComposeOrchestrator, auto-detecting the runtime (podman is preferred
// per §11.4.161 rootless mandate).
package containers

import (
	"context"
	"fmt"
	"path/filepath"

	"digital.vasic.containers/pkg/compose"
	"digital.vasic.containers/pkg/logging"
)

// Stack manages the SFTP compose stack through the containers submodule.
// It is the single entry point for all container lifecycle operations —
// no ad-hoc podman/docker commands are permitted (§11.4.76).
type Stack struct {
	orchestrator compose.ComposeOrchestrator
	project      compose.ComposeProject
	projectRoot  string
}

// Config configures the stack wrapper.
type Config struct {
	// ProjectRoot is the path to the project root directory.
	// deploy/docker-compose.yml is resolved relative to this path.
	// Required.
	ProjectRoot string

	// ComposeFile overrides the default compose file path.
	// When empty, defaults to deploy/docker-compose.yml under ProjectRoot.
	ComposeFile string

	// ProjectName overrides the compose project name (--project-name).
	// When empty, compose derives its own.
	ProjectName string
}

// New creates a Stack backed by the containers submodule's
// ComposeOrchestrator. The orchestration layer auto-detects the
// available compose command (preferring podman over docker,
// §11.4.161 rootless-first).
func New(cfg Config) (*Stack, error) {
	if cfg.ProjectRoot == "" {
		return nil, fmt.Errorf("containers: ProjectRoot is required")
	}
	if cfg.ComposeFile == "" {
		cfg.ComposeFile = filepath.Join(cfg.ProjectRoot, "deploy", "docker-compose.yml")
	}

	logger := logging.NewStdLogger("sftp-containers")
	orch, err := compose.NewDefaultOrchestrator(cfg.ProjectRoot, logger)
	if err != nil {
		return nil, fmt.Errorf("containers: create orchestrator: %w", err)
	}

	return &Stack{
		orchestrator: orch,
		project: compose.ComposeProject{
			Name: cfg.ProjectName,
			File: cfg.ComposeFile,
		},
		projectRoot: cfg.ProjectRoot,
	}, nil
}

// Start boots the compose stack. It starts services in detached mode
// and waits for them to become healthy before returning.
func (s *Stack) Start(ctx context.Context) error {
	return s.orchestrator.Up(ctx, s.project,
		compose.WithUpDetach(true),
		compose.WithWait(true),
		compose.WithWaitTimeout(60),
	)
}

// Stop tears down the compose stack gracefully.
func (s *Stack) Stop(ctx context.Context) error {
	return s.orchestrator.Down(ctx, s.project)
}

// Status returns the current status of every service in the stack.
func (s *Stack) Status(ctx context.Context) ([]compose.ServiceStatus, error) {
	return s.orchestrator.Status(ctx, s.project)
}

// HealthReport summarizes the health of the compose stack.
type HealthReport struct {
	AllHealthy bool
	Services   []ServiceHealth
}

// ServiceHealth is the health status of a single compose service.
type ServiceHealth struct {
	Name    string
	State   string
	Health  string
	Healthy bool
}

// Health checks all services and returns a report. A service is
// considered healthy when its State is "running" and its Health is
// empty (no healthcheck defined) or "healthy".
func (s *Stack) Health(ctx context.Context) (*HealthReport, error) {
	statuses, err := s.orchestrator.Status(ctx, s.project)
	if err != nil {
		return nil, fmt.Errorf("containers: status: %w", err)
	}

	report := &HealthReport{AllHealthy: true}
	for _, st := range statuses {
		healthy := st.State == "running" &&
			(st.Health == "" || st.Health == "healthy")
		report.Services = append(report.Services, ServiceHealth{
			Name:    st.Name,
			State:   st.State,
			Health:  st.Health,
			Healthy: healthy,
		})
		if !healthy {
			report.AllHealthy = false
		}
	}
	return report, nil
}

// IsReady returns true when all services are running and healthy.
func (s *Stack) IsReady(ctx context.Context) bool {
	report, err := s.Health(ctx)
	if err != nil {
		return false
	}
	return report.AllHealthy
}

// ComposeFile returns the path to the compose file in use.
func (s *Stack) ComposeFile() string {
	return s.project.File
}
