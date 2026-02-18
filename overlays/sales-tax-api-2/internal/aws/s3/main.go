package s3

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	"backend-sales-tax/configs"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Service interface {
	Upload(ctx context.Context, filePath string, fileName string, src []byte) (string, error)
	GetSignedURL(ctx context.Context, hostedUrl string, config *Config) (string, error)
	GetMetaData(ctx context.Context, hostedUrl string) (*S3FileMetaData, error)
	GetFileStream(ctx context.Context, hostedUrl string) (io.ReadCloser, error)
	ListObjects(ctx context.Context, prefix string) ([]string, error)
	DeleteObject(ctx context.Context, filePath string, fileName string) error
}

type DefaultS3Service struct {
	client    *s3.Client
	bucket    string
	presigner *s3.PresignClient
}

type Config struct {
	ContentType        *string
	ContentDisposition *string
	ExpiryTime         time.Duration
}

func (c *Config) configureHeaders(input *s3.GetObjectInput) {
	if c.ContentType != nil {
		input.ResponseContentType = c.ContentType
	}
	if c.ContentDisposition != nil {
		input.ResponseContentDisposition = c.ContentDisposition
	}
}

// getSignedUrlConfig provides default values for URLConfig
func getSignedUrlConfig() Config {
	return Config{
		ExpiryTime: time.Minute * 20,
	}
}

func NewDefaultS3Service() (*DefaultS3Service, error) {
	cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(configs.GetENV().AWS_REGION))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS configuration: %v", err)
	}

	var s3Options []func(*s3.Options)
	if endpointURL := os.Getenv("AWS_ENDPOINT_URL"); endpointURL != "" {
		s3Options = append(s3Options, func(o *s3.Options) {
			o.BaseEndpoint = aws.String(endpointURL)
			o.UsePathStyle = true
		})
	}

	client := s3.NewFromConfig(cfg, s3Options...)
	presigner := s3.NewPresignClient(client)

	return &DefaultS3Service{
		client:    client,
		bucket:    configs.GetENV().AWS_BUCKET,
		presigner: presigner,
	}, nil
}

func (s *DefaultS3Service) GetFileStream(ctx context.Context, hostedUrl string) (io.ReadCloser, error) {
	objectKey, err := extractObjectKeyFromURL(hostedUrl)
	if err != nil {
		return nil, err
	}

	object, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(objectKey),
	})

	if err != nil {
		return nil, err
	}

	return object.Body, nil
}

func (s *DefaultS3Service) Upload(ctx context.Context, filePath string, fileName string, fileBytes []byte) (string, error) {

	if s.client == nil {
		return "", fmt.Errorf("S3 client is nil")
	}

	sanitizedFileName := sanitizeFileName(fileName)

	key := fmt.Sprintf("%s/%s", filePath, sanitizedFileName)

	// TODO (aashish): This is a temporary solution to set the content type of the file.
	contentType := "application/octet-stream"
	if strings.HasSuffix(sanitizedFileName, ".csv") {
		contentType = "text/csv"
	} else if strings.HasSuffix(sanitizedFileName, ".pdf") {
		contentType = "application/pdf"
	}

	_, createError := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(fileBytes),
		ContentType: aws.String(contentType),
	})

	if createError != nil {
		log.Printf("Error putting object to S3: %v", createError)
		return "", fmt.Errorf("failed to upload file: %v", createError)
	}

	location := fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s",
		s.bucket,
		configs.GetENV().AWS_REGION,
		key,
	)

	return location, nil
}

func (s *DefaultS3Service) GetSignedURL(ctx context.Context, hostedUrl string, config *Config) (string, error) {
	objectKey, err := extractObjectKeyFromURL(hostedUrl)
	if err != nil {
		return "", err
	}

	// If no config is provided, use default configuration
	if config == nil {
		defaultConfig := getSignedUrlConfig()
		config = &defaultConfig
	}

	objectInput := &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(objectKey),
	}

	config.configureHeaders(objectInput)

	presignedURL, err := s.presigner.PresignGetObject(ctx, objectInput, func(opts *s3.PresignOptions) {
		opts.Expires = config.ExpiryTime
	})
	if err != nil {
		return "", fmt.Errorf("failed to generate pre-signed URL: %v", err)
	}

	return presignedURL.URL, nil
}

type S3FileMetaData struct {
	Size               int64
	ContentType        string
	ContentDisposition string
	LastModified       time.Time
	Metadata           map[string]string
	HostedUrl          string
	Name               string
}

func (s *DefaultS3Service) GetMetaData(ctx context.Context, hostedUrl string) (*S3FileMetaData, error) {
	objectKey, err := extractObjectKeyFromURL(hostedUrl)
	if err != nil {
		return nil, err
	}

	// Get the metadata of the object
	object, err := s.client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(objectKey),
	})

	if err != nil {
		return nil, fmt.Errorf("failed to get metadata of the object: %v", err)
	}

	// get the file name from the object key
	fileName := strings.Split(objectKey, "/")[len(strings.Split(objectKey, "/"))-1]

	metadata := &S3FileMetaData{
		Metadata: object.Metadata,
		Name:     fileName,
	}

	if object.ContentLength != nil {
		metadata.Size = *object.ContentLength
	}
	if object.ContentType != nil {
		metadata.ContentType = *object.ContentType
	}
	if object.ContentDisposition != nil {
		metadata.ContentDisposition = *object.ContentDisposition
	}
	if object.LastModified != nil {
		metadata.LastModified = *object.LastModified
	}

	return metadata, nil
}

// Helper function to extract object key from S3 URL
func extractObjectKeyFromURL(s3URL string) (string, error) {
	parsedURL, err := url.Parse(s3URL)
	if err != nil {
		return "", fmt.Errorf("failed to parse S3 URL: %v", err)
	}

	// The object key is the path of the URL without the leading '/'
	objectKey := parsedURL.Path[1:]
	return objectKey, nil
}

// sanitizeFileName sanitizes the input file name to make it safe for S3
func sanitizeFileName(fileName string) string {
	// Ensure the file name is in lowercase
	fileName = strings.ToLower(fileName)

	// Extract the file extension if it exists
	var extension string
	if idx := strings.LastIndex(fileName, "."); idx != -1 {
		extension = fileName[idx:]
		fileName = fileName[:idx]
	}

	// Replace spaces with underscores
	fileName = strings.ReplaceAll(fileName, " ", "_")

	// Allow only lowercase letters, numbers, periods, hyphens, and underscores
	reg := regexp.MustCompile(`[^a-z0-9._-]+`)
	fileName = reg.ReplaceAllString(fileName, "_")

	// Ensure the file name starts and ends with a letter or number
	fileName = strings.Trim(fileName, "._-")

	// Limit the base file name to 1024 characters, accounting for the extension length
	maxBaseLength := 1024 - len(extension)
	if len(fileName) > maxBaseLength {
		fileName = fileName[:maxBaseLength]
	}

	// Return the sanitized file name with its extension
	return fileName + extension
}

func (s *DefaultS3Service) ListObjects(ctx context.Context, prefix string) ([]string, error) {
	if s.client == nil {
		return nil, fmt.Errorf("S3 client is nil")
	}

	var objects []string
	paginator := s3.NewListObjectsV2Paginator(s.client, &s3.ListObjectsV2Input{
		Bucket: aws.String(s.bucket),
		Prefix: aws.String(prefix),
	})

	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("failed to list objects: %v", err)
		}

		for _, obj := range page.Contents {
			if obj.Key == nil {
				continue
			}

			// Construct the full S3 URL for the object
			objectURL := fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s",
				s.bucket,
				configs.GetENV().AWS_REGION,
				*obj.Key,
			)
			objects = append(objects, objectURL)
		}
	}

	return objects, nil
}

func (s *DefaultS3Service) DeleteObject(ctx context.Context, filePath string, fileName string) error {
	if s.client == nil {
		return fmt.Errorf("S3 client is nil")
	}

	// Extract the object key from the URL
	objectKey, err := extractObjectKeyFromURL(fileName)
	if err != nil {
		return fmt.Errorf("failed to extract object key from URL: %v", err)
	}

	// Delete the object
	_, err = s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(objectKey),
	})
	if err != nil {
		return fmt.Errorf("failed to delete object %s: %v", objectKey, err)
	}

	// Wait until the object is actually deleted
	waiter := s3.NewObjectNotExistsWaiter(s.client)
	err = waiter.Wait(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(objectKey),
	}, 30*time.Second) // Wait up to 30 seconds

	if err != nil {
		return fmt.Errorf("failed to confirm object deletion %s: %v", objectKey, err)
	}

	return nil
}
